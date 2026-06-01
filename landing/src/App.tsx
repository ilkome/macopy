import { Nav } from "./components/Nav";
import { Hero } from "./components/Hero";
import { Features } from "./components/Features";
import { Hotkeys } from "./components/Hotkeys";
import { HowItWorks } from "./components/HowItWorks";
import { Privacy } from "./components/Privacy";
import { Install } from "./components/Install";
import { Footer } from "./components/Footer";

export default function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Features />
        <Hotkeys />
        <HowItWorks />
        <Privacy />
        <Install />
      </main>
      <Footer />
    </>
  );
}
