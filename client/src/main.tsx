import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { Toaster } from "./components/ui/sonner.tsx";
import { ScannerProvider } from "./lib/ScannerContext.tsx";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ScannerProvider>
      <App />
      <Toaster />
    </ScannerProvider>
  </StrictMode>
);
