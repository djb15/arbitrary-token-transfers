// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.25;

import {
  GasTokenPrice, GasTokenPriceLib,
  AccountOverhead, AccountOverheadLib,
  AccountSizeCost, AccountSizeCostLib
} from "./ParamLibs.sol";

error InvalidSolanaLayout(uint256 value);

//store everything in one slot and make reads and writes cheap (no struct in memory nonsense)
type SolanaFeeParams is uint256;
library SolanaFeeParamsLib {
  // layout (low to high bits - i.e. in packed struct order) - unit:
  //  6 bytes gasTokenPrice    - μusd/sol (=> min: 1e-6 usd/sol, max: ~1e8 usd/sol)
  //  4 bytes accountOverhead  - lamports
  //  4 bytes accountSizeCost  - lamports/byte
  // 18 bytes currently unused

  uint256 private constant GAS_TOKEN_PRICE_SIZE = GasTokenPriceLib.BYTE_SIZE * 8;
  uint256 private constant GAS_TOKEN_PRICE_OFFSET = 0;
  uint256 private constant GAS_TOKEN_PRICE_WRITE_MASK =
    ~(((1 << GAS_TOKEN_PRICE_SIZE) - 1) << GAS_TOKEN_PRICE_OFFSET);

  uint256 private constant ACCOUNT_OVERHEAD_SIZE = AccountOverheadLib.BYTE_SIZE * 8;
  uint256 private constant ACCOUNT_OVERHEAD_OFFSET =
    GAS_TOKEN_PRICE_OFFSET + GAS_TOKEN_PRICE_SIZE;
  uint256 private constant ACCOUNT_OVERHEAD_WRITE_MASK =
    ~(((1 << ACCOUNT_OVERHEAD_SIZE) - 1) << ACCOUNT_OVERHEAD_OFFSET);

  uint256 private constant ACCOUNT_SIZE_COST_SIZE = AccountSizeCostLib.BYTE_SIZE * 8;
  uint256 private constant ACCOUNT_SIZE_COST_OFFSET =
    ACCOUNT_OVERHEAD_OFFSET + ACCOUNT_OVERHEAD_SIZE;
  uint256 private constant ACCOUNT_SIZE_COST_WRITE_MASK =
    ~(((1 << ACCOUNT_SIZE_COST_SIZE) - 1) << ACCOUNT_SIZE_COST_OFFSET);

  uint256 private constant LAYOUT_WRITE_MASK = //all unused bits are 1
    ACCOUNT_OVERHEAD_WRITE_MASK & ACCOUNT_SIZE_COST_WRITE_MASK & GAS_TOKEN_PRICE_WRITE_MASK;

  function checkedWrap(uint256 value) internal pure returns (SolanaFeeParams) { unchecked {
    if ((value & LAYOUT_WRITE_MASK) != 0)
      revert InvalidSolanaLayout(value);

    return SolanaFeeParams.wrap(value);
  }}

  function gasTokenPrice(
    SolanaFeeParams params
  ) internal pure returns (GasTokenPrice) { unchecked {
    return GasTokenPrice.wrap(
      uint48(SolanaFeeParams.unwrap(params) >> GAS_TOKEN_PRICE_OFFSET)
    );
  }}

  function gasTokenPrice(
    SolanaFeeParams params,
    GasTokenPrice gasTokenPrice_
  ) internal pure returns (SolanaFeeParams) { unchecked {
    return SolanaFeeParams.wrap(
      (SolanaFeeParams.unwrap(params) & GAS_TOKEN_PRICE_WRITE_MASK) |
      (uint256(GasTokenPrice.unwrap(gasTokenPrice_)) << GAS_TOKEN_PRICE_OFFSET)
    );
  }}

  function accountOverhead(
    SolanaFeeParams params
  ) internal pure returns (AccountOverhead) { unchecked {
    return AccountOverhead.wrap(
      uint32(SolanaFeeParams.unwrap(params) >> ACCOUNT_OVERHEAD_OFFSET)
    );
  }}

  function accountOverhead(
    SolanaFeeParams params,
    AccountOverhead accountOverhead_
  ) internal pure returns (SolanaFeeParams) { unchecked {
    return SolanaFeeParams.wrap(
      (SolanaFeeParams.unwrap(params) & ACCOUNT_OVERHEAD_WRITE_MASK) |
      (uint256(AccountOverhead.unwrap(accountOverhead_)) << ACCOUNT_OVERHEAD_OFFSET)
    );
  }}

  function accountSizeCost(
    SolanaFeeParams params
  ) internal pure returns (AccountSizeCost) { unchecked {
    return AccountSizeCost.wrap(
      uint32(SolanaFeeParams.unwrap(params) >> ACCOUNT_SIZE_COST_OFFSET)
    );
  }}

  function accountSizeCost(
    SolanaFeeParams params,
    AccountSizeCost accountSizeCost_
  ) internal pure returns (SolanaFeeParams) { unchecked {
    return SolanaFeeParams.wrap(
      (SolanaFeeParams.unwrap(params) & ACCOUNT_SIZE_COST_WRITE_MASK) |
      (uint256(AccountSizeCost.unwrap(accountSizeCost_)) << ACCOUNT_SIZE_COST_OFFSET)
    );
  }}
}

using SolanaFeeParamsLib for SolanaFeeParams global;