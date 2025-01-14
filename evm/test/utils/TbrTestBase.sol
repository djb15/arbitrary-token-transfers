// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.25;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SolanaFeeParams } from "../../src/price-oracle/assets/types/SolanaFeeParams.sol";
import { EvmFeeParams } from "../../src/price-oracle/assets/types/EvmFeeParams.sol";
import { ITokenBridge } from "wormhole-sdk/interfaces/ITokenBridge.sol";
import { BytesParsing } from "wormhole-sdk/libraries/BytesParsing.sol";
import { IWormhole } from "wormhole-sdk/interfaces/IWormhole.sol";
import { IWETH } from "wormhole-sdk/interfaces/token/IWETH.sol";
import { IPriceOracle } from "../../src/price-oracle/IPriceOracle.sol";
import { PriceOracle } from "../../src/price-oracle/PriceOracle.sol";
import { Proxy } from "wormhole-sdk/proxy/Proxy.sol";
import { reRevert } from "wormhole-sdk/Utils.sol";
import { IPermit2 } from "permit2/IPermit2.sol";
import { TbrExposer } from "./TbrExposer.sol";
import { Tbr } from "tbr/Tbr.sol";
import "forge-std/Test.sol";
import {
  PricePerByte,
  GasPrice,
  GasTokenPrice,
  AccountOverhead,
  AccountSizeCost
} from "../../src/price-oracle/assets/types/ParamLibs.sol";

contract TbrTestBase is Test {
  using BytesParsing for bytes;

  uint16  SOLANA_CHAIN_ID = 1;
  uint16  HOME_CHAIN_ID   = 2;
  uint16  EVM_CHAIN_ID    = 3;

  // Arbitrum data
  uint16  EVM_L2_CHAIN_ID = 23;
  address EVM_L2_TOKEN_WETH_TOKEN = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address EVM_L2_TOKEN_BRIDGE_ADDRESS = 0x0b2402144Bb366A632D14B83F244D2e0e21bD39c;
  bytes32 WETH_CANONICAL_ADDRESS = 0x000000000000000000000000C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  address      immutable owner;
  address      immutable admin;
  address      immutable feeRecipient;

  IPermit2     immutable permit2;
  address      immutable oracle;
  ITokenBridge immutable tokenBridge;
  IWETH        immutable gasToken;
  bool         immutable gasErc20TokenizationIsExplicit;
  
  IERC20Metadata immutable usdt;
  IWormhole      immutable wormholeCore;

  address     tbrImplementation;
  PriceOracle priceOracle;
  TbrExposer  tbrExposer;
  Tbr         tbr;

  constructor() {
    owner         = makeAddr("owner");
    admin         = makeAddr("admin");
    feeRecipient  = makeAddr("feeRecipient");

    permit2       = IPermit2(makeAddr("permit2"));
    oracle        = makeAddr("oracle");
    tokenBridge   = ITokenBridge(vm.envAddress("TEST_TOKEN_BRIDGE_ADDRESS"));
    gasToken      = IWETH(vm.envAddress("TEST_WETH_ADDRESS"));
    gasErc20TokenizationIsExplicit = true;

    usdt          = IERC20Metadata(vm.envAddress("TEST_USDT_ADDRESS"));
    wormholeCore  = IWormhole(vm.envAddress("TEST_WORMHOLE_ADDRESS"));
  }

  function _setUp1() internal virtual { }

  function setUp() public {
    uint8 adminCount = 1;

    vm.mockCall(
      address(oracle),
      abi.encodeWithSelector(IPriceOracle.get1959.selector),
      abi.encode(abi.encodePacked(uint16(HOME_CHAIN_ID)))
    );

    tbrImplementation = address(new Tbr(
      permit2,
      tokenBridge,
      oracle,
      gasToken,
      gasErc20TokenizationIsExplicit
    ));

    tbr = Tbr(payable(new Proxy(
      tbrImplementation,
      abi.encodePacked(
        feeRecipient,
        owner,
        adminCount,
        admin
      )
    )));

    tbrExposer = new TbrExposer(
      permit2,
      tokenBridge,
      oracle,
      gasToken,
      gasErc20TokenizationIsExplicit
    );

    setUpOracle();
    _setUp1();
  }

  function invokeStaticTbr(bytes memory encoded) view internal returns (bytes memory data) {
    (bool success, bytes memory result) = address(tbr).staticcall(encoded);
    if (!success) {
      reRevert(result);
    }
    (uint length,) = result.asUint256Unchecked(32);
    (data,) = result.sliceUnchecked(64, length);
  }

  function invokeTbr(bytes memory encoded) internal returns (bytes memory data) {
    (bool success, bytes memory result) = address(tbr).call(encoded);
    if (!success) {
      reRevert(result);
    }
    (uint length,) = result.asUint256Unchecked(32);
    (data,) = result.sliceUnchecked(64, length);
  }

  function invokeTbr(bytes memory encoded, uint value) internal returns (bytes memory data) {
    (bool success, bytes memory result) = address(tbr).call{value: value}(encoded);
    if (!success) {
      reRevert(result);
    }
    (uint length,) = result.asUint256Unchecked(32);
    (data,) = result.sliceUnchecked(64, length);
  }

  function setUpOracle() internal {
    address assistant = makeAddr("assistant");
    EvmFeeParams evmFeeParams;
    evmFeeParams = evmFeeParams.pricePerByte(PricePerByte.wrap(0));
    evmFeeParams = evmFeeParams.gasPrice(GasPrice.wrap(1e6));
    evmFeeParams = evmFeeParams.gasTokenPrice(GasTokenPrice.wrap(1e12));

    EvmFeeParams evmL2FeeParams;
    evmL2FeeParams = evmL2FeeParams.pricePerByte(PricePerByte.wrap(1e6));
    evmL2FeeParams = evmL2FeeParams.gasPrice(GasPrice.wrap(1e6));
    evmL2FeeParams = evmL2FeeParams.gasTokenPrice(GasTokenPrice.wrap(1e12));

    SolanaFeeParams solanaFeeParams;
    solanaFeeParams = solanaFeeParams.accountOverhead(AccountOverhead.wrap(1e9)); 
    solanaFeeParams = solanaFeeParams.accountSizeCost(AccountSizeCost.wrap(1e9));
    solanaFeeParams = solanaFeeParams.gasTokenPrice(GasTokenPrice.wrap(1e12));

    vm.mockCall(
      address(wormholeCore),
      abi.encodeWithSelector(wormholeCore.chainId.selector),
      abi.encode(HOME_CHAIN_ID)
    );

    priceOracle = PriceOracle(address(new Proxy(
      address(new PriceOracle(wormholeCore)),
      abi.encodePacked(
        owner,
        uint8(1),
        admin,
        assistant,
        HOME_CHAIN_ID,
        evmFeeParams,
        EVM_CHAIN_ID,
        evmFeeParams,
        EVM_L2_CHAIN_ID,
        evmL2FeeParams,
        SOLANA_CHAIN_ID,
        solanaFeeParams
      )
    )));
  }
}