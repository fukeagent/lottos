import { user } from '../data/mockData';
import { ShieldCheck, ShieldAlert, ShieldX } from 'lucide-react';

export const EligibilityPanel = () => {
  const isEligible = user.status === 'Eligible';
  const isForfeited = user.status === 'Forfeited';
  const isAtRisk = user.status === 'At Risk';

  return (
    <div className="glass-card p-6 md:p-8 flex flex-col h-full">
      <h2 className="text-xl font-bold mb-6">Your Status</h2>

      <div className={`rounded-xl p-4 mb-6 border flex items-start gap-3 ${
        isEligible ? 'bg-primary/10 border-primary/20' :
        isForfeited ? 'bg-danger/10 border-danger/20' :
        isAtRisk ? 'bg-accent/10 border-accent/20' :
        'bg-gray-800 border-gray-700'
      }`}>
        {isEligible && <ShieldCheck className="text-primary mt-1 shrink-0" />}
        {isForfeited && <ShieldX className="text-danger mt-1 shrink-0" />}
        {isAtRisk && <ShieldAlert className="text-accent mt-1 shrink-0" />}
        {!isEligible && !isForfeited && !isAtRisk && <ShieldAlert className="text-gray-400 mt-1 shrink-0" />}

        <div>
          <h3 className={`font-semibold mb-1 ${
            isEligible ? 'text-primary' :
            isForfeited ? 'text-danger' :
            isAtRisk ? 'text-accent' :
            'text-gray-400'
          }`}>
            {isEligible && "You are eligible."}
            {isAtRisk && "At Risk"}
            {isForfeited && "Forfeited"}
          </h3>
          <p className="text-sm text-gray-300 leading-relaxed">
            {isEligible && "Keep your balance above your round-start amount until trigger."}
            {isAtRisk && "Do not sell below your round-start balance or you will forfeit this round."}
            {isForfeited && "You dipped below your round-start balance. You cannot win this round, but you can qualify again next round."}
          </p>
        </div>
      </div>

      <div className="space-y-4 flex-grow">
        <div className="flex justify-between items-center pb-3 border-b border-gray-800">
          <span className="text-gray-400 text-sm">Your Balance</span>
          <span className="text-white font-medium">{user.balance}</span>
        </div>

        <div className="flex justify-between items-center pb-3 border-b border-gray-800">
          <span className="text-gray-400 text-sm">Round-Start Balance</span>
          <span className="text-white font-medium">{user.startBalance}</span>
        </div>

        <div className="flex justify-between items-center">
          <span className="text-gray-400 text-sm">Current Round Weight</span>
          <span className="text-white font-medium">{user.currentWeight}</span>
        </div>
      </div>

      <div className="mt-6 pt-4 border-t border-gray-800">
         <p className="text-xs text-gray-500 text-center">
           Buying more during a round helps future rounds, not the current one.
         </p>
      </div>
    </div>
  );
};
