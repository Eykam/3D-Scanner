import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { Switch } from "@/components/ui/switch";
import { Slider } from "@/components/ui/slider";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
import { Progress } from "@/components/ui/progress";
import { toast } from "sonner";
import { Settings, Play, Pause, RotateCcw, Download } from "lucide-react";
import { MAX_HORIZONTAL_STEPS, MAX_VERTICAL_STEPS, Status } from "./Config";
import { useScannerContext } from "./lib/ScannerContext";

export default function Overlay() {
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);

  // Settings state
  const [highQuality, setHighQuality] = useState(false);
  const [renderSpeed, setRenderSpeed] = useState(50);
  const [showWireframe, setShowWireframe] = useState(false);
  const [enableShadows, setEnableShadows] = useState(true);

  const { setRadPoints, status, progress } = useScannerContext();

  // / Mock 3D model details
  const modelDetails = {
    name: "Heightmap Scanner",
  };

  const getStatusColor = (status: Status) => {
    switch (status) {
      case "Initializing":
        return "bg-yellow-500";
      case "Ready" || "Done":
        return "bg-green-500";
      case "Offline":
        return "bg-red-500";
      case "Scanning":
        return "bg-blue-500";
      default:
        return "bg-gray-500";
    }
  };

  const toggleScanning = async () => {
    const newStatus = status === "Scanning" ? "Paused" : "Scanning";

    const res = await fetch("/status", {
      method: "POST",
      body: JSON.stringify({ status: newStatus }),
    });

    if (!res.ok) {
      throw Error("Failed to toggle Scanning: " + res.status);
    }

    toast(
      newStatus === "Paused"
        ? "The 3D model rendering has been paused."
        : "The 3D model rendering has begun."
    );
  };

  async function resetScan() {
    const res = await fetch("/status", {
      method: "POST",
      body: JSON.stringify({ status: "Restarting" }),
    });

    if (!res.ok) {
      throw Error("Failed to toggle Scanning: " + res.status);
    }

    toast("Restarting current Scan!");
  }

  const handleReset = () => {
    resetScan();
    setRadPoints([]);
  };

  const handleDownload = () => {
    toast("Downloading 3D Model as GLB");
  };

  return (
    <div className="fixed inset-0 pointer-events-none">
      <div className="absolute top-4 left-4 flex items-center space-x-2 bg-black/60 rounded-xl p-2">
        <div className={`w-3 h-3 rounded-full ${getStatusColor(status)}`} />
        <span className="text-sm font-medium text-white">{status}</span>
      </div>

      <div className="absolute right-4 top-1/2 -translate-y-1/2 flex flex-col space-y-4 pointer-events-auto">
        <Button
          onClick={toggleScanning}
          variant="default"
          size="icon"
          className="h-12 w-12 p-0 m-0 rounded-xl"
        >
          {status === "Scanning" ? (
            <Pause className="h-6 w-6" />
          ) : (
            <Play className="h-6 w-6" />
          )}
          <span className="sr-only">
            {status === "Scanning" ? "Stop" : "Start"} rendering
          </span>
        </Button>

        <Button
          onClick={handleDownload}
          variant="default"
          size="icon"
          className="h-12 w-12 p-0 m-0 rounded-xl"
        >
          <Download className="h-6 w-6" />
        </Button>

        <Button
          onClick={handleReset}
          variant="default"
          size="icon"
          className="h-12 w-12 p-0 m-0 rounded-xl"
        >
          <RotateCcw className="h-6 w-6" />
        </Button>

        <Sheet open={isSettingsOpen} onOpenChange={setIsSettingsOpen}>
          <SheetTrigger asChild>
            <Button
              variant="default"
              size="icon"
              className="h-12 w-12 rounded-xl p-0 m-0"
            >
              <Settings className="h-6 w-6" />
              <span className="sr-only">Open settings</span>
            </Button>
          </SheetTrigger>
          <SheetContent className="">
            <SheetHeader>
              <SheetTitle>Render Settings</SheetTitle>
            </SheetHeader>
            <div className="py-4 space-y-6">
              <div className="flex items-center justify-between">
                <Label
                  htmlFor="high-quality"
                  className="flex flex-col space-y-1"
                >
                  <span>High Quality</span>
                  <span className="font-normal text-sm text-muted-foreground">
                    Enables advanced rendering techniques
                  </span>
                </Label>
                <Switch
                  id="high-quality"
                  checked={highQuality}
                  onCheckedChange={setHighQuality}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="render-speed">Render Speed</Label>
                <Slider
                  id="render-speed"
                  min={0}
                  max={100}
                  step={1}
                  value={[renderSpeed]}
                  onValueChange={(value) => setRenderSpeed(value[0])}
                />
                <div className="flex justify-between text-sm text-muted-foreground">
                  <span>Slow</span>
                  <span>Fast</span>
                </div>
              </div>
              <div className="flex items-center space-x-2">
                <Checkbox
                  id="show-wireframe"
                  checked={showWireframe}
                  onCheckedChange={() => setShowWireframe(!showWireframe)}
                />
                <Label htmlFor="show-wireframe">Show Wireframe</Label>
              </div>
              <div className="flex items-center space-x-2">
                <Checkbox
                  id="enable-shadows"
                  checked={enableShadows}
                  onCheckedChange={() => setEnableShadows(!enableShadows)}
                />
                <Label htmlFor="enable-shadows">Enable Shadows</Label>
              </div>
            </div>
          </SheetContent>
        </Sheet>
      </div>

      <div className="absolute bottom-4 left-1/2 -translate-x-1/2 w-full max-w-md px-4 pointer-events-auto">
        <div className="bg-black/50 backdrop-blur-sm rounded-xl p-4 shadow-lg">
          <div className="mb-2 flex justify-between items-center">
            <h3 className="text-sm font-medium text-white">
              {modelDetails.name}
            </h3>
            <span className="text-xs text-white">
              {(progress * 100).toFixed(0)}% Complete
            </span>
          </div>
          <Progress value={progress * 100} className="mb-2 bg-gray-600 " />
          <div className="text-xs text-muted-foreground grid grid-cols-1 gap-2">
            <div>
              Vertex Count:{" "}
              {progress * MAX_VERTICAL_STEPS * MAX_HORIZONTAL_STEPS} /{" "}
              {MAX_VERTICAL_STEPS * MAX_HORIZONTAL_STEPS}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
