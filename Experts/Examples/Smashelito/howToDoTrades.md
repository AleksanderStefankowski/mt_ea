# How to do trades in MQL5 (CTrade) — reference for AI / developer

This file documents what a trade can do using the standard `CTrade` class (`#include <Trade\Trade.mqh>`). Use it when implementing or debugging EAs.

---

## Setup

- `ExtTrade.SetExpertMagicNumber(magic)` — set magic so orders/positions are tagged.
- `ExtTrade.SetDeviationInPoints(deviation)` — max slippage in points for market orders (default 10).
- `ExtTrade.SetTypeFilling(type)` — fill type (FOK/IOC) if required by broker.

---

## Order types (what you can send)

| Type | Method | When it executes |
|------|--------|-------------------|
| **Market buy** | `Buy(...)` | Immediately at ask. |
| **Market sell** | `Sell(...)` | Immediately at bid. |
| **Buy limit** | `BuyLimit(...)` | When bid ≤ trigger price. |
| **Sell limit** | `SellLimit(...)` | When ask ≥ trigger price. |
| **Buy stop** | `BuyStop(...)` | When bid ≥ trigger price. |
| **Sell stop** | `SellStop(...)` | When ask ≤ trigger price. |

---

## Open by market price

- **Buy (market)**  
  `bool Buy(double volume, string symbol = NULL, double price = 0.0, double sl = 0.0, double tp = 0.0, string comment = "");`  
  - `symbol = NULL` → current chart symbol.  
  - `price = 0` → market (current ask).  
  - Optional `sl`, `tp` in price; `0` = no SL/TP.  
  - **Comment is supported** (last parameter).

- **Sell (market)**  
  `bool Sell(double volume, string symbol = NULL, double price = 0.0, double sl = 0.0, double tp = 0.0, string comment = "");`  
  - Same as Buy but for sell at bid.

Example (like in DebugTrades):

```mql5
ExtTrade.Buy(0.01, _Symbol, 0, 0, 0, "DebugTrades_15:30_buy");
```

---

## Open by limit/stop (pending orders) — open price and size

- **Buy limit**  
  `bool BuyLimit(double volume, double price, string symbol = NULL, double sl = 0.0, double tp = 0.0, ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, datetime expiration = 0, string comment = "");`  
  - `price` = trigger/limit price (buy when market reaches this or better).  
  - `volume` = order size in lots.  
  - `sl`, `tp` = stop loss and take profit in price; `0` = none.  
  - **Comment is supported.**

- **Sell limit**  
  `bool SellLimit(volume, price, symbol, sl, tp, type_time, expiration, comment);`  
  - `price` = trigger price for the sell limit.

- **Buy stop**  
  `bool BuyStop(volume, price, symbol, sl, tp, type_time, expiration, comment);`  
  - `price` = trigger price (buy when market >= this).

- **Sell stop**  
  `bool SellStop(volume, price, symbol, sl, tp, type_time, expiration, comment);`  
  - `price` = trigger price (sell when market <= this).

Order size is always **volume** (lots). Open/trigger price is **price** for limit/stop.

---

## Setting TP and SL

- **On market order:** pass `sl` and `tp` as 4th and 5th parameters to `Buy()` / `Sell()` (in price; use `NormalizeDouble(..., _Digits)`).
- **On pending order:** pass `sl` and `tp` to `BuyLimit` / `SellLimit` / `BuyStop` / `SellStop`.
- **On already open position:**  
  `bool PositionModify(ulong ticket, double sl, double tp);`  
  or `PositionModify(symbol, sl, tp)` (modifies position by symbol).
- **On pending order:**  
  `bool OrderModify(ulong ticket, double price, double sl, double tp, ENUM_ORDER_TYPE_TIME type_time, datetime expiration, double stoplimit = 0.0);`

Use `0` for sl or tp to mean “no level” where allowed.

---

## Cancelling a pending order

- **Delete by ticket**  
  `bool OrderDelete(ulong ticket);`  
  - Removes the pending order. Use `COrderInfo` / `OrdersTotal()` to find the ticket if needed.

---

## Close by market price

- **Close position by ticket**  
  `bool PositionClose(ulong ticket, ulong deviation = ULONG_MAX);`  
  - Closes that position at market (like in DebugTrades at 16:00).

- **Close position by symbol**  
  `bool PositionClose(string symbol, ulong deviation = ULONG_MAX);`  
  - In netting: closes the net position for that symbol. In hedging: typically closes one position (e.g. first found).

- **Partial close**  
  `bool PositionClosePartial(ulong ticket, double volume, ulong deviation = ULONG_MAX);`  
  - Closes only part of the position (by volume).

- **Close by opposite position (hedging)**  
  `bool PositionCloseBy(ulong ticket, ulong ticket_by);`  
  - Closes one position by another (e.g. hedge close).

Example (like in DebugTrades):

```mql5
ExtTrade.PositionClose(ticket);
```

---

## Comments

- **Adding a comment is possible** on all trade methods that take a `comment` parameter:  
  `Buy`, `Sell`, `BuyLimit`, `SellLimit`, `BuyStop`, `SellStop`, and the generic `OrderOpen` / `PositionOpen`.  
- Comment appears on the order/position and in the result (e.g. `ResultComment()` after send).  
- Broker may truncate or restrict length; keep it short.

---

## Reading the result after a trade

After any `Buy`, `Sell`, `PositionClose`, `OrderDelete`, etc.:

- `ExtTrade.ResultRetcode()` — result code (e.g. 10009 = done).
- `ExtTrade.ResultRetcodeDescription()` — human-readable string (e.g. "done at 6848.1").
- `ExtTrade.ResultOrder()` — order ticket.
- `ExtTrade.ResultDeal()` — deal ticket.
- `ExtTrade.ResultVolume()` — executed volume.
- `ExtTrade.ResultPrice()` — execution price.
- `ExtTrade.ResultComment()` — server message (e.g. "Request executed").

Success is typically `ResultRetcode() == 10009` (TRADE_RETCODE_DONE). Check retcode for partial fill, rejection, etc.

---

## Order lifetime (pending orders)

- **ORDER_TIME_GTC** — Good Till Cancel (default).  
- **ORDER_TIME_DAY** — Valid for the current trading day.  
- **ORDER_TIME_SPECIFIED** — Valid until `expiration` (datetime).  
- **ORDER_TIME_SPECIFIED_DAY** — Valid until end of day of `expiration`.

Pass `type_time` and `expiration` in `BuyLimit` / `SellLimit` / `BuyStop` / `SellStop` (and in `OrderModify` for pending orders).

---

## Summary table

| Action | Method | Main parameters |
|--------|--------|------------------|
| Open market buy | `Buy(volume, symbol, 0, sl, tp, comment)` | volume, optional sl/tp, comment |
| Open market sell | `Sell(volume, symbol, 0, sl, tp, comment)` | same |
| Open buy limit | `BuyLimit(volume, price, symbol, sl, tp, type_time, expiration, comment)` | price = trigger |
| Open sell limit | `SellLimit(...)` | price = trigger |
| Open buy stop | `BuyStop(...)` | price = trigger |
| Open sell stop | `SellStop(...)` | price = trigger |
| Set/change SL/TP on position | `PositionModify(ticket, sl, tp)` | ticket, new sl, new tp |
| Modify pending order | `OrderModify(ticket, price, sl, tp, type_time, expiration, stoplimit)` | new price, sl, tp, time |
| Cancel pending order | `OrderDelete(ticket)` | order ticket |
| Close position at market | `PositionClose(ticket)` or `PositionClose(symbol)` | ticket or symbol |
| Partial close | `PositionClosePartial(ticket, volume)` | ticket, volume to close |

All of the above support or affect **order type**, **order size (volume)**, **open/trigger price**, **TP/SL**, **cancelling pending**, **close by market**, **open by market**, and **comments**, as described in the sections above.
