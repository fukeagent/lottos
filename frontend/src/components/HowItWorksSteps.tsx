import { ShoppingCart, PlayCircle, Shield, Gift, Coins } from 'lucide-react';

export const HowItWorksSteps = () => {
  const steps = [
    {
      icon: <ShoppingCart className="text-primary w-6 h-6" />,
      title: "1. Buy $FORTUNE",
      desc: "Hold the token in your wallet to become eligible for future rounds."
    },
    {
      icon: <PlayCircle className="text-secondary w-6 h-6" />,
      title: "2. Round Starts",
      desc: "Your lottery weight is fixed from your balance at the start of the round."
    },
    {
      icon: <Shield className="text-accent w-6 h-6" />,
      title: "3. Hold the Line",
      desc: "If your balance drops below your round-start balance before trigger, you forfeit this round."
    },
    {
      icon: <Gift className="text-primary w-6 h-6" />,
      title: "4. Fortune Draw",
      desc: "A winner is selected from the remaining diamond-handed holders."
    },
    {
      icon: <Coins className="text-secondary w-6 h-6" />,
      title: "5. Direct ETH Payout",
      desc: "The winner receives ETH directly. No manual claim needed for normal payouts."
    }
  ];

  return (
    <section id="how-it-works" className="py-20 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto border-t border-gray-800">
      <div className="text-center mb-16">
        <h2 className="text-3xl md:text-4xl font-bold mb-4">How It Works</h2>
        <p className="text-gray-400 max-w-2xl mx-auto">Simple, transparent, and completely onchain. Here's how you play the Merry Fortune draw.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {steps.map((step, index) => (
          <div key={index} className="glass-card p-6 hover:border-gray-600 transition-colors">
            <div className="w-12 h-12 bg-surface rounded-xl flex items-center justify-center mb-4 border border-gray-800">
              {step.icon}
            </div>
            <h3 className="text-lg font-bold mb-2 text-white">{step.title}</h3>
            <p className="text-gray-400 text-sm leading-relaxed">{step.desc}</p>
          </div>
        ))}

        <div className="glass-card p-6 bg-primary/5 border-primary/20 lg:col-span-1 flex flex-col justify-center">
           <p className="text-primary text-sm font-medium text-center">
             Note: Buying more during a round helps future rounds, not the current one.
           </p>
        </div>
      </div>
    </section>
  );
};
