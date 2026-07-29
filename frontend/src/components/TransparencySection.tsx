import { Code, CheckCircle, Lock, Cpu, Zap, Shield } from 'lucide-react';

export const TransparencySection = () => {
  const features = [
    { icon: <Cpu className="w-5 h-5" />, title: "Onchain Draws" },
    { icon: <Zap className="w-5 h-5" />, title: "Permissionless Execution" },
    { icon: <CheckCircle className="w-5 h-5" />, title: "Direct ETH Payouts" },
    { icon: <Lock className="w-5 h-5" />, title: "Strict Diamond Hands" },
    { icon: <Shield className="w-5 h-5" />, title: "Config Freeze" },
    { icon: <Code className="w-5 h-5" />, title: "Open Source" },
  ];

  return (
    <section className="py-20 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto border-t border-gray-800">
      <div className="flex flex-col lg:flex-row gap-12 items-center">
        <div className="flex-1 space-y-6">
          <h2 className="text-3xl md:text-4xl font-bold">Transparent by Design</h2>
          <p className="text-gray-400 leading-relaxed text-lg">
            Merry Fortune is designed around transparent onchain rules. The draw lifecycle, forfeiture rules, payouts, and round status are readable from contracts.
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-4">
             {features.map((feature, i) => (
                <div key={i} className="flex items-center gap-3 text-gray-300">
                  <div className="text-primary">{feature.icon}</div>
                  <span className="font-medium">{feature.title}</span>
                </div>
             ))}
          </div>

          <div className="mt-8 p-4 bg-surface border border-gray-800 rounded-xl">
             <p className="text-xs text-gray-500 italic">
               MVP randomness uses blockhash-based randomness. Prize caps and future VRF upgrades should be clearly documented when contracts are live.
             </p>
          </div>
        </div>

        <div className="flex-1 w-full relative">
           <div className="absolute inset-0 bg-gradient-to-r from-primary/10 to-secondary/10 blur-3xl rounded-full"></div>
           <div className="glass-card p-6 font-mono text-sm text-gray-400 relative z-10 overflow-hidden">
<pre className="overflow-x-auto">
{`function checkEligibility(
  address user,
  uint256 roundId
) public view returns (bool) {
  Round memory round = rounds[roundId];
  UserStake memory stake = stakes[user];

  if (stake.currentBalance <
      stake.roundStartBalance) {
      return false; // Forfeited
  }

  return true;
}`}
</pre>
           </div>
        </div>
      </div>
    </section>
  );
};
