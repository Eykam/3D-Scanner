import { Cylinder } from "@react-three/drei/core/shapes";
import PointCloud from "./PointCloud";

// const TURNTABLE_DIAMETER = 0.1524;
const TURNTABLE_DIAMETER = 15.24;

export default function Scene() {
  return (
    <>
      <axesHelper args={[5]} position={[0, 2, 0]} />
      <Cylinder
        // args={[TURNTABLE_DIAMETER / 2, TURNTABLE_DIAMETER / 2, 0.002, 32]}
        args={[TURNTABLE_DIAMETER / 2, TURNTABLE_DIAMETER / 2, 0.2, 32]}
        castShadow
        receiveShadow
      >
        <meshBasicMaterial color={0xe7cfb4} />
      </Cylinder>
      <PointCloud />
    </>
  );
}
