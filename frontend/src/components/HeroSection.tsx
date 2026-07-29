import { currentRound, user } from '../data/mockData';
import { ArrowRight, Trophy } from 'lucide-react';

export const HeroSection = () => {
  return (
    <section className="pt-32 pb-16 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto flex flex-col lg:flex-row gap-12 items-center">
      <div className="flex-1 text-center lg:text-left space-y-8">
        <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-primary/10 border border-primary/20 text-primary text-sm font-medium mb-4">
          <Trophy size={16} />
          <span>Onchain Fortune</span>
        </div>

        <h1 className="text-5xl lg:text-7xl font-bold leading-tight">
          Merry Fortune <br/>
          <span className="text-primary">Hold your fortune.</span><br/>
          <span className="text-accent">Win the draw.</span>
        </h1>

        <p className="text-lg text-gray-400 max-w-2xl mx-auto lg:mx-0 leading-relaxed">
          $FORTUNE is a diamond-hands lottery token where your round weight is fixed at the start. Dip below it before the draw trigger and you forfeit that round.
        </p>

        <div className="flex flex-col sm:flex-row gap-4 justify-center lg:justify-start">
          <button className="btn-primary flex items-center justify-center gap-2">
            Buy $FORTUNE
            <ArrowRight size={18} />
          </button>
          <button className="btn-secondary">
            View Current Round
          </button>
        </div>
      </div>

      <div className="flex-1 w-full max-w-md">
        <div className="glass-card p-8 relative overflow-hidden">
          <div className="absolute top-0 right-0 w-64 h-64 bg-primary/10 rounded-full blur-3xl -mr-32 -mt-32"></div>

          <div className="relative z-10 space-y-6">
            <div>
              <p className="text-gray-400 text-sm font-medium mb-1">Current Prize Pool</p>
              <h2 className="text-5xl font-bold text-white tracking-tight">{currentRound.prizePoolEth} ETH</h2>
            </div>

            <div className="space-y-4">
              <div className="flex justify-between items-center pb-4 border-b border-gray-800">
                <span className="text-gray-400">Round Status</span>
                <span className="text-accent font-medium">{currentRound.status}</span>
              </div>

              <div className="flex justify-between items-center pb-4 border-b border-gray-800">
                <span className="text-gray-400">Time to Trigger</span>
                <span className="text-white font-mono">{currentRound.timeToTrigger}</span>
              </div>

              <div className="flex justify-between items-center pb-4 border-b border-gray-800">
                <span className="text-gray-400">Eligible Holders</span>
                <span className="text-white">{currentRound.eligibleHolders}</span>
              </div>

              <div className="flex justify-between items-center">
                <span className="text-gray-400">Your Status</span>
                <span className={`font-medium ${user.status === 'Eligible' ? 'text-primary' : 'text-danger'}`}>
                  {user.status}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
