// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.25;

import { CHAIN_ID_SOLANA } from "wormhole-sdk/constants/Chains.sol";
import { BytesParsing } from "wormhole-sdk/libraries/BytesParsing.sol";
import {
  GasTokenPrice,
  GasPrice,
  PricePerByte,
  AccountOverhead,
  AccountSizeCost,
  BaseFee,
  GasDropoff
} from "./types/ParamLibs.sol";
import { EvmFeeParams, EvmFeeParamsLib } from "./types/EvmFeeParams.sol";
import { SolanaFeeParams } from "./types/SolanaFeeParams.sol";
import { 
  PriceOracleConfig,
  ConfigState,
  configState
} from "./PriceOracleConfig.sol";
import { 
  AccessControlState,
  accessControlState,
  NotAuthorized,
  Role,
  senderRole
} from "./sharedComponents/AccessControl.sol";
import { IWormhole } from "wormhole-sdk/interfaces/IWormhole.sol";
import "./PriceOracleIds.sol";

struct FeeParamsState {
  // chainId => fee parameters of that chain
  mapping(uint16 => uint256) chainToFeeParams;
}

// keccak256("FeeParamsState") - 1
bytes32 constant FEE_PARAMS_STORAGE_SLOT =
  0x390950e512c08746510d8189287f633f84012f0678caa6bc6558847bdd158b23;

function feeParamsState() pure returns (FeeParamsState storage state) {
  assembly ("memory-safe") {
    state.slot := FEE_PARAMS_STORAGE_SLOT
  }
}

//the additional gas cost is likely worth the cost of being able to reconstruct old fees
event FeeParamsUpdated(uint16 indexed chainId, bytes32 feeParams);

/**
 * Chain id 0 is invalid.
 */
error InvalidChainId();
/**
 * The query is not recognized.
 */
error InvalidPriceQuery(uint8 query);
/**
 * The command is not supported by the chain.
 */
error ChainNotSupportedByCommand(uint16 chainId, uint8 command);

// TODO: add non-native tokens prices

abstract contract PriceOraclePrices is PriceOracleConfig {
  using BytesParsing for bytes;

  uint16 private immutable _localChainId;

  constructor(IWormhole wormholeCore) {
    _localChainId = wormholeCore.chainId();
  }

  function _getFeeParams(uint16 targetChainId) internal view returns (uint256) {
    return feeParamsState().chainToFeeParams[targetChainId];
  }

  function _setFeeParams(uint16 targetChainId, uint256 feeParams) internal {
    feeParamsState().chainToFeeParams[targetChainId] = feeParams;
    emit FeeParamsUpdated(targetChainId, bytes32(feeParams));
  }

  function _batchPriceCommands(
    bytes calldata commands,
    uint offset
  ) internal returns (uint) {
    ConfigState storage state = configState();
    bool isAssistant;
    Role role = senderRole();
    if (Role.Owner == role || Role.Admin == role)
      isAssistant = false;
    else if (msg.sender == state.assistant)
      isAssistant = true;
    else
      revert NotAuthorized();

    uint256 feeParams;
    uint16 currentChain = 0;
    uint remainingCommands;
    (remainingCommands, offset) = commands.asUint8CdUnchecked(offset);
    for (uint i = 0; i < remainingCommands; ++i) {
      uint8 command;
      uint16 updateChain;
      (command, offset) = commands.asUint8CdUnchecked(offset);
      (updateChain, offset) = commands.asUint16CdUnchecked(offset);

      if (updateChain == 0)
        revert InvalidChainId();

      if (currentChain != updateChain) {
        if (currentChain != 0)
          _setFeeParams(currentChain, feeParams);

        currentChain = updateChain;
        feeParams = _getFeeParams(currentChain);
      }

      if (currentChain != CHAIN_ID_SOLANA) {
        if (command == FEE_PARAMS_ID) {
          uint256 feeParamsRaw;
          (feeParamsRaw, offset) = commands.asUint256CdUnchecked(offset);
          feeParams = EvmFeeParams.unwrap(EvmFeeParamsLib.checkedWrap(feeParamsRaw));
        }
        else if (command == GAS_PRICE_ID) {
          uint32 gasPrice;
          (gasPrice, offset) = commands.asUint32CdUnchecked(offset);
          feeParams = EvmFeeParams.unwrap(
            EvmFeeParams.wrap(feeParams).gasPrice(GasPrice.wrap(gasPrice))
          );
        }
        else if (command == PRICE_PER_BYTE_ID) {
          uint32 pricePerByte;
          (pricePerByte, offset) = commands.asUint32CdUnchecked(offset);
          feeParams = EvmFeeParams.unwrap(
            EvmFeeParams.wrap(feeParams).pricePerByte(PricePerByte.wrap(pricePerByte))
          );
        }
        else if (command == GAS_TOKEN_PRICE_ID) {
          GasTokenPrice gasTokenPrice;
          (gasTokenPrice, offset) = _parseGasTokenPrice(commands, offset);
          feeParams = EvmFeeParams.unwrap(
            EvmFeeParams.wrap(feeParams).gasTokenPrice(gasTokenPrice)
          );
        }
        else
          revert ChainNotSupportedByCommand(currentChain, command);
      }
      else {
        if (command == GAS_TOKEN_PRICE_ID) {
          GasTokenPrice gasTokenPrice;
          (gasTokenPrice, offset) = _parseGasTokenPrice(commands, offset);
          feeParams = SolanaFeeParams.unwrap(
            SolanaFeeParams.wrap(feeParams).gasTokenPrice(gasTokenPrice)
          );
        }
        else if (command == ACCOUNT_OVERHEAD_ID || command == ACCOUNT_SIZE_COST_ID) {
          if (isAssistant)
            revert NotAuthorized();

          uint32 val;
          (val, offset) = commands.asUint32CdUnchecked(offset);
          feeParams = SolanaFeeParams.unwrap(
            (command == ACCOUNT_OVERHEAD_ID)
            ? SolanaFeeParams.wrap(feeParams).accountOverhead(AccountOverhead.wrap(val))
            : SolanaFeeParams.wrap(feeParams).accountSizeCost(AccountSizeCost.wrap(val))
          );
        }
        else
          revert ChainNotSupportedByCommand(currentChain, command);
      }
    }

    if (currentChain != 0)
      _setFeeParams(currentChain, feeParams);

    return offset;
  }

  function _batchPriceQueries(
    bytes calldata queries,
    uint offset
  ) internal view returns (bytes memory, uint) {
    bytes memory ret;
    uint remainingQueries;
    (remainingQueries, offset) = queries.asUint8CdUnchecked(offset);
    
    for (uint i = 0; i < remainingQueries; ++i) {
      uint8 query;
      (query, offset) = queries.asUint8CdUnchecked(offset);
      if (query == EVM_TX_QUOTE_ID) {
        uint16 targetChainId;
        GasDropoff gasDropoff;
        uint32 gas;
        BaseFee baseFee;
        uint32 billedSize;
        (targetChainId, offset) = queries.asUint16CdUnchecked(offset);
        (gasDropoff,    offset) = _parseGasDropoff(queries, offset);
        (gas,           offset) = queries.asUint32CdUnchecked(offset);
        (baseFee,       offset) = _parseBaseFee(queries, offset);
        (billedSize,    offset) = queries.asUint32CdUnchecked(offset);

        ret = abi.encodePacked(
          ret,
          evmTransactionQuote(targetChainId, gasDropoff, gas, baseFee, billedSize)
        );
      }
      else if (query == SOLANA_TX_QUOTE_ID) {
        GasDropoff gasDropoff;
        uint8 numberOfSpawnedAccounts;
        uint32 totalSizeOfAccounts;
        BaseFee baseFee;
        (gasDropoff,              offset) = _parseGasDropoff(queries, offset);
        (numberOfSpawnedAccounts, offset) = queries.asUint8CdUnchecked(offset);
        (totalSizeOfAccounts,     offset) = queries.asUint32CdUnchecked(offset);
        (baseFee,                 offset) = _parseBaseFee(queries, offset);

        ret = abi.encodePacked(
          ret,
          solanaTransactionQuote(gasDropoff, numberOfSpawnedAccounts, totalSizeOfAccounts, baseFee)
        );
      }
      else if (query == QUERY_FEE_PARAMS_ID) {
        uint16 targetChainId;
        (targetChainId, offset) = queries.asUint16CdUnchecked(offset);
        ret = abi.encodePacked(ret, _getFeeParams(targetChainId));
      }
      else if (query == CHAIN_ID_ID)
        ret = abi.encodePacked(ret, _localChainId);
      else
        revert InvalidPriceQuery(query);
    }

    return (ret, offset);
  }

  function _parseGasTokenPrice(
    bytes calldata commands,
    uint offset
  ) private pure returns (GasTokenPrice, uint) {
    uint48 gasTokenPrice;
    (gasTokenPrice, offset) = commands.asUint48CdUnchecked(offset);
    return (GasTokenPrice.wrap(gasTokenPrice), offset);
  }

  function _parseGasDropoff(
    bytes calldata commands,
    uint offset
  ) private pure returns (GasDropoff, uint) {
    uint32 gasDropoff;
    (gasDropoff, offset) = commands.asUint32CdUnchecked(offset);
    return (GasDropoff.wrap(gasDropoff), offset);
  }

  function _parseBaseFee(
    bytes calldata commands,
    uint offset
  ) private pure returns (BaseFee, uint) {
    uint32 baseFee;
    (baseFee, offset) = commands.asUint32CdUnchecked(offset);
    return (BaseFee.wrap(baseFee), offset);
  }

  /**
   * @param targetChainId The chainId of the target chain
   * @param gasDropoff amount of target chain native token (with 18 decimals = wei) to be converted
   * @param gas amount of gas units
   * @param baseFee additional flat fee for the relayer in usd with 18 decimals
   * @param billedSize the billable bytes of the call (typically the tx size)
   * @return quote quote in current chain native asset (with 18 decimals = wei)
   */
  function evmTransactionQuote(
    uint16 targetChainId,
    GasDropoff gasDropoff,
    uint gas,
    BaseFee baseFee,
    uint billedSize
  ) private view returns (uint) { unchecked {
    EvmFeeParams targetChainParams = EvmFeeParams.wrap(_getFeeParams(targetChainId));
    EvmFeeParams localChainParams = EvmFeeParams.wrap(_getFeeParams(_localChainId));

    // targetGasToken + gas * targetGasToken/gas + bytes * targetGasToken/byte = targetGasToken
    uint totalTargetGasToken = gasDropoff.from()
                               + gas * targetChainParams.gasPrice().from()
                               + billedSize * targetChainParams.pricePerByte().from();

    // targetGasToken * usd/targetGasToken = usd * 1e18
    uint totalTargetUsd = totalTargetGasToken * targetChainParams.gasTokenPrice().from();

    // (usd * 1e18 + usd * 1e18) / (usd/localGasToken) = localGasToken
    return (totalTargetUsd + baseFee.from() * 1e18)  / localChainParams.gasTokenPrice().from();
  }}

  /**
   * @param gasDropoff amount of target chain native token (with 18 decimals = wei) to be converted
   * @param numberOfSpawnedAccounts number of accounts to be spawned
   * @param totalSizeOfAccounts total size of the accounts to be spawned in bytes
   * @param baseFee additional flat fee for the relayer in usd (with 18 decimals)
   * @return quote quote in current chain native asset (with 18 decimals = wei)
   */
  function solanaTransactionQuote(
    GasDropoff gasDropoff,
    uint numberOfSpawnedAccounts,
    uint totalSizeOfAccounts,
    BaseFee baseFee
  ) private view returns (uint) { unchecked {
    SolanaFeeParams solanaParams = SolanaFeeParams.wrap(_getFeeParams(CHAIN_ID_SOLANA));
    EvmFeeParams localChainParams = EvmFeeParams.wrap(_getFeeParams(_localChainId));

    // sol + number * sol + bytes * sol/byte = sol
    uint totalSol = gasDropoff.from()
                    + numberOfSpawnedAccounts * solanaParams.accountOverhead().from()
                    + totalSizeOfAccounts * solanaParams.accountSizeCost().from();

    // sol * usd/sol = usd * 1e18
    uint totalTargetUsd = totalSol * solanaParams.gasTokenPrice().from();

    // (usd * 1e18 + usd * 1e18) / usd/eth = eth
    return (totalTargetUsd + baseFee.from() * 1e18) / localChainParams.gasTokenPrice().from();
  }}
}
