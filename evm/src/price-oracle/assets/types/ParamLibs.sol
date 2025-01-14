// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.25;

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! NOTE !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// !!! All unit libs return prices via their `from` functions as fixed point uints !!!
// !!!   with 18 decimals in "human units" (i.e. eth, not wei, sol, not lamports). !!!
// !!! So if 1 eth = $1000, then GasTokenPrice.from() returns 1e21 [usd/gasToken]. !!!
// !!! Likewise, `to` functions expect prices in the same format.                  !!!
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

// Summary (since most of this file is boilerplate):
//
//      Type       │ External Repr │ Internal Repr │ Bytes
//─────────────────┼───────────────┼───────────────┼───────
//  GasTokenPrice  │ usd/gasToken  │ µusd/gasToken │   6
//     GasPrice    │ gasToken/gas  │   Mwei/gas    │   4
//  PricePerByte   │ gasToken/byte │   Mwei/byte   │   4
// AccountOverhead │      sol      │   lamports    │   4
// AccountSizeCost │    sol/byte   │ lamports/byte │   4
//    GasDropoff   │    gasToken   │   µgasToken   │   4
//     BaseFee     │      usd      │     µusd      │   4

error LosingAllPrecision(uint256 , uint256 divisor);
error ExceedsMax(uint256 stored, uint256 max);

function checkedUnitDiv(uint val, uint divisor, uint max) pure returns (uint) { unchecked {
  if (val == 0)
    return 0;

  uint ret = val / divisor;
  if (ret == 0)
    revert LosingAllPrecision(val, divisor);

  if (ret > max)
    revert ExceedsMax(ret, max);

  return ret;
}}

//gasToken is a more general term for elements of the set {sol, eth, avax, ...}
type GasTokenPrice is uint48;
//external repr: usd/gasToken with 18 decimals (1 usd/eth => 1e18, usd NOT µusd!)
library GasTokenPriceLib {
  //WARNING: any changes must be reflected in the typescript SDK!
  uint internal constant BYTE_SIZE = 6;
  uint private constant UNIT = 1e12; //µusd/gasToken (1e6 * 1e12 = 1e18)

  function to(uint val) internal pure returns (GasTokenPrice) {
    uint tmp = checkedUnitDiv(val, UNIT, type(uint48).max);

    //skip unneccessary cleanup
    uint48 ret;
    assembly ("memory-safe") { ret := tmp }

    return GasTokenPrice.wrap(ret);
  }

  function from(GasTokenPrice val) internal pure returns (uint) { unchecked {
    return uint(GasTokenPrice.unwrap(val)) * UNIT;
  }
}}
using GasTokenPriceLib for GasTokenPrice global;

//cost of 1 consumed gas unit
type GasPrice is uint32;
//external repr: gasToken/gas with 18 decimals (eth/gas NOT Gwei/gas!)
library GasPriceLib {
  //WARNING: any changes must be reflected in the typescript SDK!
  uint internal constant BYTE_SIZE = 4;
  uint private constant UNIT = 1e6;

  function to(uint val) internal pure returns (GasPrice) { unchecked {
    uint tmp = checkedUnitDiv(val, UNIT, type(uint32).max);

    //skip unneccessary cleanup
    uint32 ret;
    assembly ("memory-safe") { ret := tmp }

    return GasPrice.wrap(ret);
  }}

  function from(GasPrice val) internal pure returns (uint) { unchecked {
    return uint(GasPrice.unwrap(val)) * UNIT;
  }
}}
using GasPriceLib for GasPrice global;

//per byte cost of calldata on L2s
type PricePerByte is uint32;
//external repr: gasToken/byte (of calldata) with 18 decimals (eth/byte NOT Gwei/gas!)
library PricePerByteLib {
  //WARNING: any changes must be reflected in the typescript SDK!
  uint internal constant BYTE_SIZE = 4;
  uint private constant UNIT = 1e6;

  function to(uint val) internal pure returns (PricePerByte) { unchecked {
    uint tmp = checkedUnitDiv(val, UNIT, type(uint32).max);

    //skip unneccessary cleanup
    uint32 ret;
    assembly ("memory-safe") { ret := tmp }

    return PricePerByte.wrap(ret);
  }}

  function from(PricePerByte val) internal pure returns (uint) { unchecked {
    return uint(PricePerByte.unwrap(val)) * UNIT;
  }
}}
using PricePerByteLib for PricePerByte global;

//fixed overhead of spawning a new solana account
type AccountOverhead is uint32;
//external repr: sol with 18 decimals (NOT lamports!)
//At time of writing: 890_880 lamports (and likely won't change)
//So likely returned value:  890_880_000_000_000 = 0.00089088 sol
library AccountOverheadLib {
  //WARNING: any changes must be reflected in the typescript SDK!
  uint internal constant BYTE_SIZE = 4;
  uint private constant UNIT = 1e9; //stored in lamports

  function to(uint256 val) internal pure returns (AccountOverhead) { unchecked {
    uint tmp = checkedUnitDiv(val, UNIT, type(uint32).max);

    //skip unneccessary cleanup
    uint32 ret;
    assembly ("memory-safe") { ret := tmp }

    return AccountOverhead.wrap(ret);
  }}

  function from(AccountOverhead val) internal pure returns (uint256) { unchecked {
    return uint256(AccountOverhead.unwrap(val)) * UNIT;
  }
}}
using AccountOverheadLib for AccountOverhead global;

//per byte cost of solana account data
type AccountSizeCost is uint32;
//external repr: sol/byte (of account data) with 18 decimals (NOT lamports/byte!)
//At time of writing: 6_960 lamports/byte (alson likely won't change).
//So likely returned value: 6_960_000_000_000 = 0.00000696 sol/byte
library AccountSizeCostLib {
  //WARNING: any changes must be reflected in the typescript SDK!
  uint internal constant BYTE_SIZE = 4;
  uint private constant UNIT = 1e9; //stored in lamports/byte

  function to(uint256 val) internal pure returns (AccountSizeCost) { unchecked {
    uint tmp = checkedUnitDiv(val, UNIT, type(uint32).max);

    //skip unneccessary cleanup
    uint32 ret;
    assembly ("memory-safe") { ret := tmp }

    return AccountSizeCost.wrap(ret);
  }}

  function from(AccountSizeCost val) internal pure returns (uint256) { unchecked {
    return uint256(AccountSizeCost.unwrap(val)) * UNIT;
  }
}}
using AccountSizeCostLib for AccountSizeCost global;

//requested amount of additional gas dropoff for a delivery
type GasDropoff is uint32;
//external repr: gasToken with 18 decimals
library GasDropoffLib {
  //WARNING: any changes must be reflected in the typescript SDK!
  uint internal constant BYTE_SIZE = 4;
  uint private constant UNIT = 1e12; //specified in µgasToken

  function to(uint256 val) internal pure returns (GasDropoff) { unchecked {
    uint tmp = checkedUnitDiv(val, UNIT, type(uint32).max);

    //skip unneccessary cleanup
    uint32 ret;
    assembly ("memory-safe") { ret := tmp }

    return GasDropoff.wrap(ret);
  }}

  function from(GasDropoff val) internal pure returns (uint256) { unchecked {
    return uint256(GasDropoff.unwrap(val)) * UNIT;
  }
}}
using GasDropoffLib for GasDropoff global;

type BaseFee is uint32;
//external repr: usd with 18 decimals
library BaseFeeLib {
  //WARNING: any changes must be reflected in the typescript SDK!
  uint internal constant BYTE_SIZE = 4;
  uint private constant UNIT = 1e12; //specified in µusd

  function to(uint256 val) internal pure returns (BaseFee) { unchecked {
    uint tmp = checkedUnitDiv(val, UNIT, type(uint32).max);

    //skip unneccessary cleanup
    uint32 ret;
    assembly ("memory-safe") { ret := tmp }

    return BaseFee.wrap(ret);
  }}

  function from(BaseFee val) internal pure returns (uint256) { unchecked {
    return uint256(BaseFee.unwrap(val)) * UNIT;
  }
}}
using BaseFeeLib for BaseFee global;
