import { useState } from 'react';
import { ChevronDown, ChevronUp, HelpCircle } from 'lucide-react';

export const FAQSection = () => {
  const [openIndex, setOpenIndex] = useState<number | null>(0);

  const faqs = [
    {
      q: "What is Merry Fortune?",
      a: "$FORTUNE is a lottery token where users buy and hold through a diamond-hands epoch to win a prize pool in native ETH."
    },
    {
      q: "Can I sell and buy back?",
      a: "No. If your balance drops below your round-start balance before trigger, you forfeit that round. Buying back does not restore eligibility."
    },
    {
      q: "Can I buy more during a round?",
      a: "Yes, but it helps future rounds only. Your current-round weight is fixed at round start."
    },
    {
      q: "When does the winner get paid?",
      a: "The winner receives ETH directly after the draw is triggered. No manual claim is needed for normal payouts."
    },
    {
      q: "What happens if everyone forfeits?",
      a: "The round expires cleanly and the prize returns to the available lottery pool for the next round."
    },
    {
      q: "Is this affiliated with Robinhood?",
      a: "No. Merry Fortune is an independent token project."
    }
  ];

  const toggleFAQ = (index: number) => {
    setOpenIndex(openIndex === index ? null : index);
  };

  return (
    <section id="faq" className="py-20 px-4 sm:px-6 lg:px-8 max-w-3xl mx-auto border-t border-gray-800">
      <div className="text-center mb-12">
        <h2 className="text-3xl md:text-4xl font-bold mb-4 flex items-center justify-center gap-3">
          <HelpCircle className="text-primary" /> FAQ
        </h2>
        <p className="text-gray-400">Everything you need to know about the lottery rules.</p>
      </div>

      <div className="space-y-4">
        {faqs.map((faq, index) => (
          <div
            key={index}
            className="glass-card overflow-hidden transition-all duration-200"
          >
            <button
              className="w-full px-6 py-4 flex justify-between items-center text-left focus:outline-none"
              onClick={() => toggleFAQ(index)}
            >
              <span className="font-semibold text-lg text-white">{faq.q}</span>
              {openIndex === index ? (
                <ChevronUp className="text-primary flex-shrink-0" />
              ) : (
                <ChevronDown className="text-gray-500 flex-shrink-0" />
              )}
            </button>

            <div
              className={`px-6 pb-4 text-gray-400 leading-relaxed transition-all duration-200 ${
                openIndex === index ? 'block' : 'hidden'
              }`}
            >
              {faq.a}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
};
