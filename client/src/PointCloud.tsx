import { useEffect, useMemo, useRef } from "react";
import {
  DISTANCE_TO_CENTER,
  MAX_HORIZONTAL_STEPS,
  MAX_VERTICAL_STEPS,
  Point as TPoint,
  VERTICAL_STEP_SIZE_MM,
} from "./Config";
import { useScannerContext } from "./lib/ScannerContext";
import * as THREE from "three";
import { useFrame } from "@react-three/fiber";
import { Sphere } from "@react-three/drei/core/shapes";

// function processHeightData(radPoints) {
//   // Initialize a 2D array or a flat array matching sphere vertices
//   const heightData = new Array(MAX_VERTICAL_STEPS * MAX_HORIZONTAL_STEPS).fill(
//     0
//   );

//   radPoints.forEach((point) => {
//     const { horizontal, vertical, distance } = point;
//     const index = horizontal + vertical * MAX_HORIZONTAL_STEPS;
//     heightData[index] = point.vertical;
//   });

//   return heightData;
// }

function projectTo3D(point: TPoint) {
  const { distance, horizontal, vertical } = point;
  const scale = 0.1;

  const distanceFromOrigin = DISTANCE_TO_CENTER - distance;
  const anglePerStep = (2 * Math.PI) / MAX_HORIZONTAL_STEPS;
  const currRad = anglePerStep * horizontal;

  const xCoord = distanceFromOrigin * Math.cos(currRad);
  const zCoord = distanceFromOrigin * Math.sin(currRad);

  return [
    xCoord * scale,
    vertical * VERTICAL_STEP_SIZE_MM * scale,
    zCoord * scale,
  ];
}

export default function PointCloud() {
  const { radPoints } = useScannerContext();
  const pointsRef = useRef<THREE.Points>(null!);
  const color = new THREE.Color(128 / 255, 0, 1);

  const geometry = useMemo(() => new THREE.BufferGeometry(), []);

  useEffect(() => {
    if (radPoints.length > 0) {
      const positions = new Float32Array(radPoints.length * 3);
      const colors = new Float32Array(radPoints.length * 3);

      radPoints.forEach((point, i) => {
        const [x, y, z] = projectTo3D(point);
        const index = i * 3;
        positions[index] = x;
        positions[index + 1] = y;
        positions[index + 2] = z;
        colors[index] =
          point.horizontal % 25 === 0 && point.horizontal % 50 !== 0
            ? 0
            : color.r;
        colors[index + 1] =
          point.horizontal % 25 === 0 && point.horizontal % 50 !== 0
            ? 0
            : point.horizontal == 1
            ? 1
            : color.g;
        colors[index + 2] = color.b;
      });

      geometry.setAttribute(
        "position",
        new THREE.BufferAttribute(positions, 3)
      );
      geometry.setAttribute("color", new THREE.BufferAttribute(colors, 3));
    }
  }, [radPoints, geometry, color]);

  useFrame(() => {
    if (
      pointsRef.current &&
      geometry.attributes.position &&
      geometry.attributes.color
    ) {
      geometry.attributes.position.needsUpdate = true;
      geometry.attributes.color.needsUpdate = true;
    }
  });

  return (
    <>
      <points ref={pointsRef} geometry={geometry} castShadow receiveShadow>
        <pointsMaterial
          size={5}
          sizeAttenuation={false}
          vertexColors
          transparent
          depthTest={false}
          toneMapped={false}
        />
      </points>
      <Sphere
        args={[(MAX_VERTICAL_STEPS * VERTICAL_STEP_SIZE_MM * 10) / 2, 200, 35]}
        position={[0, (MAX_VERTICAL_STEPS * VERTICAL_STEP_SIZE_MM * 10) / 2, 0]}
        castShadow
        receiveShadow
      >
        <meshBasicMaterial color="orange" />
      </Sphere>
    </>
  );
}
