import { pastRounds } from '../data/mockData';
import { History, ExternalLink, Filter } from 'lucide-react';

export const RoundHistoryTable = () => {
  return (
    <section id="history" className="py-20 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto border-t border-gray-800">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-8 gap-4">
        <div>
          <h2 className="text-3xl font-bold mb-2 flex items-center gap-2">
             <History className="text-primary" /> Past Rounds
          </h2>
          <p className="text-gray-400">History of previous draws and winners</p>
        </div>

        <div className="flex gap-2">
           <button className="flex items-center gap-2 bg-surface hover:bg-gray-800 text-gray-300 px-3 py-1.5 rounded-lg border border-gray-700 transition-colors text-sm">
              <Filter size={14} /> Filter
           </button>
           <div className="flex bg-surface rounded-lg p-1 border border-gray-800">
              <button className="px-3 py-1 text-sm bg-gray-800 rounded-md text-white">All</button>
              <button className="px-3 py-1 text-sm text-gray-400 hover:text-white">Paid</button>
              <button className="px-3 py-1 text-sm text-gray-400 hover:text-white">Expired</button>
           </div>
        </div>
      </div>

      <div className="glass-card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm text-left">
            <thead className="text-xs text-gray-400 uppercase bg-surface/50 border-b border-gray-800">
              <tr>
                <th className="px-6 py-4">Round</th>
                <th className="px-6 py-4">Winner</th>
                <th className="px-6 py-4">Prize</th>
                <th className="px-6 py-4">Eligible / Forfeited</th>
                <th className="px-6 py-4">Status</th>
                <th className="px-6 py-4 text-right">Tx</th>
              </tr>
            </thead>
            <tbody>
              {pastRounds.map((round) => (
                <tr key={round.id} className="border-b border-gray-800/50 hover:bg-surface/30 transition-colors">
                  <td className="px-6 py-4 font-medium text-white">#{round.id}</td>
                  <td className="px-6 py-4 font-mono text-gray-300">{round.winner}</td>
                  <td className="px-6 py-4 font-bold text-accent">{round.prize}</td>
                  <td className="px-6 py-4">
                    <span className="text-primary">{round.eligibleHolders}</span>
                    <span className="text-gray-500 mx-1">/</span>
                    <span className="text-danger">{round.forfeitedHolders}</span>
                  </td>
                  <td className="px-6 py-4">
                    <span className={`badge ${round.status === 'Paid' ? 'badge-success' : 'badge-neutral'}`}>
                      {round.status}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-right">
                    <a href="#" className="inline-flex items-center text-gray-400 hover:text-white transition-colors">
                      <span className="font-mono text-xs mr-1">{round.tx}</span>
                      <ExternalLink size={12} />
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
};
