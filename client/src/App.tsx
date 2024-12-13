import { Canvas } from "@react-three/fiber";
import Scene from "./Scene";
import { OrbitControls } from "@react-three/drei";

import Overlay from "./Overlay";

function App() {
  return (
    <>
      <Canvas
        camera={{ near: 0.1, far: 1000, position: [25, 8, 0], fov: 75 }}
        style={{ width: "100vw", height: "100vh" }}
      >
        <Scene />
        <ambientLight intensity={1} castShadow />
        <directionalLight
          position={[30, 20, 10]}
          intensity={1.5}
          castShadow
          shadow-mapSize-width={2048}
          shadow-mapSize-height={2048}
          shadow-camera-far={50}
          shadow-camera-left={-10}
          shadow-camera-right={10}
          shadow-camera-top={10}
          shadow-camera-bottom={-10}
        />

        <OrbitControls enableDamping dampingFactor={0.05} />
        <gridHelper args={[200, 200]} />
      </Canvas>
      <Overlay />
    </>
  );
}

export default App;
