import {
  MAX_HORIZONTAL_STEPS,
  MAX_VERTICAL_STEPS,
  Point,
  Status,
} from "@/Config";
import {
  createContext,
  useState,
  useContext,
  ReactNode,
  useEffect,
} from "react";

interface IScannerContext {
  status: Status;
  progress: number;
  radPoints: Point[];
  setProgress: React.Dispatch<React.SetStateAction<number>>;
  setRadPoints: (points: Point[]) => void;
}

// Create the context with a default value
const ScannerContext = createContext<IScannerContext | undefined>(undefined);

// Create a provider component
interface ScannerContextProps {
  children: ReactNode;
}

export function ScannerProvider({ children }: ScannerContextProps) {
  const [status, setStatus] = useState<Status>("Offline");
  const [progress, setProgress] = useState(0);
  const [radPoints, setRadPoints] = useState<Point[]>([]);

  useEffect(() => {
    if (status === "Scanning") {
      const fetchData = async () => {
        try {
          const response = await fetch("/data");
          if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
          }
          const newPoints = await response.json();

          if (newPoints.length > 0) {
            setRadPoints((old) => {
              setProgress(
                (old.length + newPoints.length) /
                  (MAX_VERTICAL_STEPS * MAX_HORIZONTAL_STEPS)
              );
              return [...old, ...newPoints];
            });
          }
        } catch (error) {
          console.error("Error fetching data:", error);
        }
      };

      const interval = setInterval(fetchData, 1000);

      return () => clearInterval(interval);
    }
  }, [status]);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const response = await fetch("/status");
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }
        const { status } = await response.json();
        console.log("Scanner Status:", status);

        setStatus(status);
      } catch (error) {
        console.error("Error fetching data:", error);
      }
    };

    const interval = setInterval(fetchData, 1000);

    return () => clearInterval(interval);
  }, []);

  return (
    <ScannerContext.Provider
      value={{ status, progress, radPoints, setRadPoints, setProgress }}
    >
      {children}
    </ScannerContext.Provider>
  );
}

// Custom hook for using the context
export function useScannerContext() {
  const context = useContext(ScannerContext);
  if (context === undefined) {
    throw new Error("useMyContext must be used within a MyContextProvider");
  }
  return context;
}
