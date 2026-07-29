import { Navigation } from './components/Navigation';
import { HeroSection } from './components/HeroSection';
import { RoundStatusCard } from './components/RoundStatusCard';
import { EligibilityPanel } from './components/EligibilityPanel';
import { HowItWorksSteps } from './components/HowItWorksSteps';
import { TradingStats } from './components/TradingStats';
import { RoundHistoryTable } from './components/RoundHistoryTable';
import { TransparencySection } from './components/TransparencySection';
import { FAQSection } from './components/FAQSection';

function App() {
  return (
    <div className="min-h-screen bg-background text-gray-200 font-sans selection:bg-primary/30">
      <Navigation />

      <main>
        <HeroSection />

        <section id="round" className="py-12 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <RoundStatusCard />
            <div className="md:col-span-1 h-full md:-mt-8 md:sticky md:top-24">
               <EligibilityPanel />
            </div>
          </div>
        </section>

        <HowItWorksSteps />
        <TradingStats />
        <RoundHistoryTable />
        <TransparencySection />
        <FAQSection />
      </main>

      <footer className="border-t border-gray-800 py-12 text-center text-gray-500">
        <p>© 2024 Merry Fortune. All rights reserved.</p>
        <p className="text-sm mt-2">Hold your fortune. Win the draw.</p>
      </footer>

      {/* Mobile Sticky CTA */}
      <div className="md:hidden fixed bottom-0 left-0 right-0 p-4 bg-background/90 backdrop-blur-lg border-t border-gray-800 z-50">
        <button className="w-full btn-primary py-3">
          Buy $FORTUNE / Connect Wallet
        </button>
      </div>
    </div>
  );
}

export default App;
