# 3D LIDAR Scanner & Point Cloud Visualization System

This repository contains the source code for a complete 3D LiDAR scanning solution. The system combines an ESP32-based firmware to control a LiDAR sensor and stepper motors, a backend server to aggregate scan data and provide a simple HTTP/JSON API, and a browser-based front-end client to visualize the resulting 3D point cloud in real-time. Additionally, the web client provides basic controls to start, pause, and reset scans.

## Overview

**Key Components:**

1. **ESP32 Firmware (FreeRTOS + LiDAR + Stepper Motors)**
   - Captures distance data from a VL53L1X LiDAR sensor while controlling two stepper motors:
     - **Horizontal Stepper:** Rotates a LiDAR module around its axis to capture a full 360° horizontal sweep.
     - **Vertical Stepper:** Moves the LiDAR module vertically along a rail to capture multiple horizontal sweeps at different heights.
   - The data from each measured point (distance + corresponding polar coordinates) is sent to the backend server via UDP.
   - The firmware also handles saving/loading vertical rail position from non-volatile storage (NVS), scanning states, and sensor initialization.

2. **Backend Server (Zig)**
   - Listens for UDP data packets from the ESP32 firmware.
   - Buffers collected data points and provides them through a simple HTTP interface.
   - Exposes endpoints:
     - `GET /data`: Returns the latest batch of scanned points in JSON.
     - `GET /status`: Returns the current scanner status in JSON (e.g., *Ready*, *Scanning*, *Paused*, *Done*).
     - `POST /status`: Accepts JSON commands to update the scanner’s status (e.g., start scanning, pause, restart).
   - Periodically sends keepalive packets or status updates back to the firmware, maintaining synchronization.

3. **Front-End Client (Browser-Based)**
   - A React-based UI that fetches data periodically from the backend.
   - Visualizes the point cloud data in 3D (using WebGL or a 3D library).
   - Provides user controls to start, pause, and reset the scanner via `POST /status`.
   - Displays scanner status, progress, and configuration options (e.g., render speed, wireframe mode, etc.).

## System Architecture

1. **Data Flow:**
   - The ESP32 firmware drives both stepper motors and captures LiDAR distance data at known angular and vertical positions.
   - Each reading is sent as a UDP packet to the backend.
   - The backend aggregates data points into a JSON array accessible via HTTP `GET /data`.
   - The frontend regularly polls `GET /data` to obtain new points and update its 3D visualization in real-time.
   - User inputs from the frontend (e.g., start/stop scanning) are sent back to the backend via `POST /status`. The backend then relays these commands to the ESP32, keeping the entire system in sync.

2. **Coordinate System:**
   - The firmware uses step counts on the motors to represent angular (horizontal) and vertical positions.
   - These polar coordinates (distance, horizontal angle, vertical position) are later converted to Cartesian coordinates in the backend or frontend before visualization.

3. **Communication Protocols:**
   - **Firmware <-> Backend:** UDP for data points and status updates, TCP/HTTP for serving frontend files and endpoints.
   - **Backend <-> Client:** HTTP (JSON data) for data retrieval and status control, with static assets served over HTTP as well.

## Repository Structure

- **Firmware (ESP32):**  
  - Written in C and C++ and built with ESP-IDF / FreeRTOS.
  - Manages LiDAR measurements, stepper motors, and NVS.
  
- **Backend (Zig):**  
  - A lightweight HTTP server using Zig’s standard library networking and JSON capabilities.
  - Handles `/data` and `/status` endpoints, and serves static frontend files.
  - Receives UDP data from ESP32, stores it in a buffer, and returns it on `GET /data`.

- **Client (React/TypeScript):**  
  - A single-page application (SPA) that fetches data from `GET /data` and displays a 3D visualization.
  - Provides user controls (start, pause, restart scanning) via `POST /status`.
  - Uses UI components (buttons, sliders, checkboxes) to configure rendering settings.

## Building and Running

### Requirements

- **Firmware:**
  - ESP32 development environment
  - [ESP-IDF](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/) installed
  - A VL53L1X LiDAR sensor wired to the designated I2C pins
  - Stepper motors with appropriate drivers connected to the specified GPIO pins
  - A stable power source and a configured Wi-Fi network

- **Backend:**
  - [Zig](https://ziglang.org/) compiler (tested with Zig 0.11.0 or newer)
  - `std` library (included with Zig)
  - A machine or server to run the backend, accessible by the ESP32 and the frontend client.

- **Frontend:**
  - Node.js and npm (LTS recommended)
  - Modern web browser

### Firmware Setup

1. **Configure Wi-Fi Credentials:**  
   Set `CONFIG_ESP_WIFI_SSID`, `CONFIG_ESP_WIFI_PASSWORD`, and other parameters in `sdkconfig` or in `Kconfig.projbuild`.
   
2. **Build and Flash:**  
   ```sh
   idf.py set-target esp32
   idf.py build
   idf.py flash monitor


### Client Setup

1. **Download Docker**
    Make sure you have Docker installed (you can skip this step if you compile the Zig backend to your native OS)
2. **Run the run.sh bash script**
   This bash script will download all the node modules required using npm. It will then bundle the javascript and html into the dist folder. Next it will build the zig project, producing a binary that will run the backend server that will serve the client bundle and copy it to the dist folder. You can then copy the dist folder to any location you would like to run the stack and run the binary.