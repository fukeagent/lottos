import { currentRound } from '../data/mockData';
import { Timer, Users, UserMinus } from 'lucide-react';

export const RoundStatusCard = () => {
  return (
    <div className="glass-card p-6 md:p-8 col-span-1 md:col-span-2">
      <div className="flex justify-between items-start mb-6">
        <div>
          <h2 className="text-2xl font-bold mb-2">Round #{currentRound.id}</h2>
          <div className="badge badge-warning">
            {currentRound.status}
          </div>
        </div>
        <div className="text-right">
          <p className="text-sm text-gray-400 mb-1">Prize Pool</p>
          <p className="text-2xl font-bold text-white">{currentRound.prizePoolEth} ETH</p>
        </div>
      </div>

      <div className="bg-background/50 rounded-xl p-4 mb-6 border border-gray-800">
        <div className="flex flex-col md:flex-row gap-4 items-center justify-between">
          <div className="flex items-center gap-3">
            <Timer className="text-accent" />
            <div>
              <p className="text-sm text-gray-400">Diamond-Hands Timer</p>
              <p className="font-mono text-lg font-medium">{currentRound.timeToTrigger}</p>
            </div>
          </div>
          <div className="h-full w-px bg-gray-800 hidden md:block"></div>
          <div className="flex items-center gap-3">
            <Users className="text-primary" />
            <div>
              <p className="text-sm text-gray-400">Eligible</p>
              <p className="text-lg font-medium">{currentRound.eligibleHolders} <span className="text-sm text-gray-500">holders</span></p>
            </div>
          </div>
          <div className="h-full w-px bg-gray-800 hidden md:block"></div>
          <div className="flex items-center gap-3">
            <UserMinus className="text-danger" />
            <div>
              <p className="text-sm text-gray-400">Forfeited</p>
              <p className="text-lg font-medium">{currentRound.forfeitedHolders} <span className="text-sm text-gray-500">holders</span></p>
            </div>
          </div>
        </div>
      </div>

      <div className="space-y-4">
        <div>
          <div className="flex justify-between text-sm mb-2">
            <span className="text-gray-400">Remaining Eligible Weight</span>
            <span className="text-white font-medium">{currentRound.remainingWeight}</span>
          </div>
          <div className="w-full bg-gray-800 rounded-full h-2.5">
            <div className="bg-primary h-2.5 rounded-full" style={{ width: '82.4%' }}></div>
          </div>
        </div>

        <div className="bg-surface border border-gray-800 rounded-lg p-4 mt-6">
          <p className="text-sm text-gray-300">
            <span className="text-white font-medium">How it works:</span> Your current-round weight is fixed when the round starts. Hold at least that balance until the trigger. If you dip below it, you lose this round's weight.
          </p>
        </div>
      </div>
    </div>
  );
};
