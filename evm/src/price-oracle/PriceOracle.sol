// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.25;

import { PriceOracleDispatcher } from "./assets/PriceOracleDispatcher.sol";
import { SolanaFeeParamsLib } from "./assets/types/SolanaFeeParams.sol";
import { BytesParsing } from "wormhole-sdk/libraries/BytesParsing.sol";
import { CHAIN_ID_SOLANA } from "wormhole-sdk/constants/Chains.sol";
import { PriceOraclePrices } from "./assets/PriceOraclePrices.sol";
import { EvmFeeParamsLib } from "./assets/types/EvmFeeParams.sol";
import { IWormhole } from "wormhole-sdk/interfaces/IWormhole.sol";

contract PriceOracle is PriceOracleDispatcher {
  using BytesParsing for bytes;

  constructor(
    IWormhole wormholeCore
  ) PriceOraclePrices(wormholeCore) {}

  //constructor of the proxy contract setting storage variables
  function _proxyConstructor(bytes calldata args) internal override {
    uint offset = 0;

    address owner;
    uint8 adminCount;
    (owner, offset) = args.asAddressCdUnchecked(offset);
    (adminCount, offset) = args.asUint8CdUnchecked(offset);

    address[] memory admins = new address[](adminCount);
    for (uint8 i = 0; i < adminCount; ++i) {
      address admin;
      (admin, offset) = args.asAddressCdUnchecked(offset);
      admins[i] = admin;
    }

    address assistant;
    (assistant, offset) = args.asAddressCdUnchecked(offset);

    _accessControlConstruction(owner, admins);
    _configConstruction(assistant);

    while (offset < args.length) {
      uint16 targetChain;
      uint256 feeParams;
      (targetChain, offset) = args.asUint16CdUnchecked(offset);
      (feeParams, offset) = args.asUint256CdUnchecked(offset);

      if (targetChain == CHAIN_ID_SOLANA)
        SolanaFeeParamsLib.checkedWrap(feeParams);
      else
        EvmFeeParamsLib.checkedWrap(feeParams);

      _setFeeParams(targetChain, feeParams);
    }
    args.checkLengthCd(offset);
  }
}
