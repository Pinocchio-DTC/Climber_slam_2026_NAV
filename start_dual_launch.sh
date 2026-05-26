#!/usr/bin/env bash
set -euo pipefail

NAV_WORKSPACE_DIR="/home/nucshao/Climber_slam_2026_NAV"
CODE_WORKSPACE_DIR="/home/nucshao/Climber_slam_2026_code"
COD_FRONT_LAUNCH="/home/nucshao/Climber_slam_2026_code/COD_Behavior/launch/cod_front_tactical.launch.py"

ROS_SETUP_FILE="${ROS_SETUP_FILE:-/opt/ros/humble/setup.bash}"
ROS_LOG_DIR="${ROS_LOG_DIR:-/tmp/ros_logs}"
INITIAL_POSE_X="${INITIAL_POSE_X:--10.0}"
INITIAL_POSE_Y="${INITIAL_POSE_Y:-0.37}"
INITIAL_POSE_Z="${INITIAL_POSE_Z:-0.0}"
INITIAL_POSE_QZ="${INITIAL_POSE_QZ:-0.002345}"
INITIAL_POSE_QW="${INITIAL_POSE_QW:-0.999997}"

check_file() {
  local path="$1"
  local hint="${2:-}"

  if [[ ! -f "$path" ]]; then
    echo "[ERROR] File not found: $path"
    if [[ -n "$hint" ]]; then
      echo "[HINT] $hint"
    fi
    exit 1
  fi
}

check_file "$ROS_SETUP_FILE"
check_file "$NAV_WORKSPACE_DIR/install/setup.bash" \
  "Please build first: cd $NAV_WORKSPACE_DIR && colcon build"
check_file "$CODE_WORKSPACE_DIR/install/setup.bash" \
  "Please build first: cd $CODE_WORKSPACE_DIR && colcon build"
check_file "$COD_FRONT_LAUNCH"

mkdir -p "$ROS_LOG_DIR"
export ROS_LOG_DIR

# ROS setup scripts may reference unset variables, so disable nounset while sourcing.
set +u
source "$ROS_SETUP_FILE"
source "$NAV_WORKSPACE_DIR/install/setup.bash"
source "$CODE_WORKSPACE_DIR/install/setup.bash"
set -u

PIDS=()

cleanup() {
  if [[ ${#PIDS[@]} -eq 0 ]]; then
    return
  fi

  echo ""
  echo "[INFO] Stopping launched processes..."
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  wait || true
}

launch_background() {
  local name="$1"
  local workdir="$2"
  shift 2

  echo "[INFO] Starting $name..."
  (
    cd "$workdir"
    "$@"
  ) &
  PIDS+=("$!")
  sleep 1
}

publish_initial_pose() {
  echo "[INFO] Publishing initial pose on /initialpose..."
  ros2 topic pub --times 3 --rate 1 /initialpose geometry_msgs/msg/PoseWithCovarianceStamped \
    "{
      header: {frame_id: 'map'},
      pose: {
        pose: {
          position: {x: ${INITIAL_POSE_X}, y: ${INITIAL_POSE_Y}, z: ${INITIAL_POSE_Z}},
          orientation: {x: 0.0, y: 0.0, z: ${INITIAL_POSE_QZ}, w: ${INITIAL_POSE_QW}}
        },
        covariance: [
          0.25, 0.0, 0.0, 0.0, 0.0, 0.0,
          0.0, 0.25, 0.0, 0.0, 0.0, 0.0,
          0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
          0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
          0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
          0.0, 0.0, 0.0, 0.0, 0.0, 0.0685
        ]
      }
    }"
}

trap cleanup INT TERM EXIT

launch_background "Livox MID360 driver" \
  "$NAV_WORKSPACE_DIR" \
  ros2 launch livox_ros_driver2 rviz_MID360_launch.py

launch_background "single Nav2 bringup" \
  "$NAV_WORKSPACE_DIR" \
  ros2 launch rm_bringup singlenav_launch.py

echo "[INFO] Waiting 2 seconds before publishing initial pose..."
sleep 2

publish_initial_pose

launch_background "COD front tactical behavior" \
  "$CODE_WORKSPACE_DIR" \
  ros2 launch "$COD_FRONT_LAUNCH"

echo "[INFO] All launch processes started. Press Ctrl+C to stop them."
wait
