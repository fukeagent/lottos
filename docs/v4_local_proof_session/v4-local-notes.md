# V4 Local Deployment Notes

## Installed Dependencies
- `v4-core` commit: `e50237c43811bd9b526eff40f26772152a42daba`

## PoolManager
- Constructor args: `address initialOwner`

## Hooks
- Permissions needed:
  - `beforeSwap` = true (`1 << 7` or `0x80`)
  - `afterSwap` = true (`1 << 6` or `0x40`)
  - `beforeSwapReturnDelta` = true (`1 << 3` or `0x08`)
  - `afterSwapReturnDelta` = true (`1 << 2` or `0x04`)
- Target mask for lowest 14 bits (or 16 bits):
  - `0x80 | 0x40 | 0x08 | 0x04 = 0xCC`
- Expected hook address: `...xxxxxxCC` (specifically, `uint160(address) & 0x3FFF == 0x00CC`)

## Native ETH Currency
- In Uniswap V4, native ETH is represented as a `Currency` where the underlying address is `address(0)`.

## Swap Delta Semantics
- `BeforeSwapDelta`: Contains `specifiedDelta` and `unspecifiedDelta`.
- `afterSwapReturnDelta`: Applies directly to the `unspecified` currency.
- `specifiedCurrency` is the input for `exactIn` and output for `exactOut`.
- `unspecifiedCurrency` is the output for `exactIn` and input for `exactOut`.
