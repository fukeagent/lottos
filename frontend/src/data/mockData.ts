export const token = {
  name: "Merry Fortune",
  ticker: "$FORTUNE",
  price: "$0.000042",
  marketCap: "$420,000",
  liquidity: "$82,000",
  volume24h: "$128,000"
};

export const currentRound = {
  id: 129,
  status: "Diamond-Hands Epoch",
  prizePoolEth: 12.42,
  eligibleHolders: 1245,
  forfeitedHolders: 83,
  remainingWeight: "82.4%",
  timeToTrigger: "18m 34s"
};

export const user = {
  connected: true,
  balance: "4,200,000",
  startBalance: "4,000,000",
  currentWeight: "0.42%",
  status: "Eligible",
  forfeited: false
};

export const pastRounds = [
  { id: 128, winner: "0xA1...9F", prize: "4.82 ETH", eligibleHolders: 1245, forfeitedHolders: 83, status: "Paid", tx: "0xdef..." },
  { id: 127, winner: "0x7B...21", prize: "3.91 ETH", eligibleHolders: 1188, forfeitedHolders: 51, status: "Paid", tx: "0xabc..." },
  { id: 126, winner: "—", prize: "—", eligibleHolders: 803, forfeitedHolders: 803, status: "Expired", tx: "0x123..." }
];

export const recentTrades = [
  { type: "buy", amount: "1,200,000", eth: "0.05", wallet: "0x4a...3c", time: "2 mins ago" },
  { type: "sell", amount: "500,000", eth: "0.021", wallet: "0x9b...1f", time: "5 mins ago" },
  { type: "buy", amount: "3,400,000", eth: "0.142", wallet: "0x2c...8e", time: "12 mins ago" },
  { type: "sell", amount: "8,200,000", eth: "0.344", wallet: "0x8a...4b", time: "18 mins ago" },
  { type: "buy", amount: "800,000", eth: "0.033", wallet: "0x1f...9d", time: "22 mins ago" }
];
