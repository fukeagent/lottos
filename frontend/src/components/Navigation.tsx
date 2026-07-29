import { Wallet } from 'lucide-react';

export const Navigation = () => {
  return (
    <nav className="fixed top-0 w-full z-50 bg-background/80 backdrop-blur-md border-b border-gray-800">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between h-16 items-center">
          <div className="flex items-center gap-2">
            <span className="text-xl font-bold text-primary">$FORTUNE</span>
          </div>

          <div className="hidden md:flex space-x-8">
            <a href="#round" className="text-gray-300 hover:text-white transition-colors text-sm font-medium">Current Round</a>
            <a href="#how-it-works" className="text-gray-300 hover:text-white transition-colors text-sm font-medium">How It Works</a>
            <a href="#trading" className="text-gray-300 hover:text-white transition-colors text-sm font-medium">Trading</a>
            <a href="#history" className="text-gray-300 hover:text-white transition-colors text-sm font-medium">History</a>
            <a href="#faq" className="text-gray-300 hover:text-white transition-colors text-sm font-medium">FAQ</a>
          </div>

          <div className="flex items-center">
            <button className="flex items-center gap-2 bg-surface hover:bg-gray-800 text-white px-4 py-2 rounded-lg border border-gray-700 transition-colors text-sm font-medium">
              <Wallet size={16} />
              <span className="hidden sm:inline">Connect Wallet</span>
            </button>
          </div>
        </div>
      </div>
    </nav>
  );
};
