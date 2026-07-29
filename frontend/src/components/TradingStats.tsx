import { token, recentTrades } from '../data/mockData';
import { TrendingUp, Activity, DollarSign, BarChart3, ExternalLink } from 'lucide-react';

export const TradingStats = () => {
  return (
    <section id="trading" className="py-20 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto border-t border-gray-800">
      <div className="flex flex-col md:flex-row justify-between items-end mb-8 gap-4">
        <div>
          <h2 className="text-3xl font-bold mb-2">Token / Trading</h2>
          <p className="text-gray-400">Live stats and recent activity for $FORTUNE</p>
        </div>
        <div className="flex gap-3">
          <button className="btn-secondary flex items-center gap-2">
            Buy <ExternalLink size={16} />
          </button>
          <button className="btn-secondary flex items-center gap-2">
            Sell <ExternalLink size={16} />
          </button>
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        <div className="glass-card p-4">
          <div className="flex items-center gap-2 text-gray-400 mb-1">
            <DollarSign size={16} /> Price
          </div>
          <div className="text-xl font-bold text-white">{token.price}</div>
        </div>
        <div className="glass-card p-4">
          <div className="flex items-center gap-2 text-gray-400 mb-1">
            <TrendingUp size={16} /> Market Cap
          </div>
          <div className="text-xl font-bold text-white">{token.marketCap}</div>
        </div>
        <div className="glass-card p-4">
          <div className="flex items-center gap-2 text-gray-400 mb-1">
            <Activity size={16} /> Liquidity
          </div>
          <div className="text-xl font-bold text-white">{token.liquidity}</div>
        </div>
        <div className="glass-card p-4">
          <div className="flex items-center gap-2 text-gray-400 mb-1">
            <BarChart3 size={16} /> 24h Volume
          </div>
          <div className="text-xl font-bold text-white">{token.volume24h}</div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 glass-card p-4 h-96 flex flex-col">
          <div className="flex justify-between items-center mb-4">
             <h3 className="font-bold text-lg">Chart</h3>
             <span className="text-xs text-gray-500">Mock Placeholder</span>
          </div>
          <div className="flex-1 bg-surface border border-gray-800 rounded-lg flex items-center justify-center text-gray-500">
             [Dexscreener Chart Placeholder]
          </div>
        </div>

        <div className="glass-card p-4 flex flex-col">
          <h3 className="font-bold text-lg mb-4">Recent Trades</h3>
          <div className="overflow-x-auto">
            <table className="w-full text-sm text-left">
              <thead className="text-xs text-gray-400 uppercase bg-surface">
                <tr>
                  <th className="px-4 py-2 rounded-tl-lg">Type</th>
                  <th className="px-4 py-2">ETH</th>
                  <th className="px-4 py-2 rounded-tr-lg">Time</th>
                </tr>
              </thead>
              <tbody>
                {recentTrades.map((trade, i) => (
                  <tr key={i} className="border-b border-gray-800">
                    <td className={`px-4 py-3 font-medium ${trade.type === 'buy' ? 'text-primary' : 'text-danger'}`}>
                      {trade.type.toUpperCase()}
                    </td>
                    <td className="px-4 py-3 text-white">{trade.eth}</td>
                    <td className="px-4 py-3 text-gray-400">{trade.time}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </section>
  );
};
