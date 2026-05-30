#!/usr/bin/env bash
set -euo pipefail

NAV_WORKSPACE_DIR="/home/nucshao/Climber_slam_2026_NAV"
CODE_WORKSPACE_DIR="/home/nucshao/Climber_slam_2026_code"
COD_FRONT_LAUNCH="/home/nucshao/Climber_slam_2026_code/COD_Behavior/launch/cod_front_tactical.launch.py"

ROS_SETUP_FILE="${ROS_SETUP_FILE:-/opt/ros/humble/setup.bash}"
ROS_LOG_DIR="${ROS_LOG_DIR:-/tmp/ros_logs}"
TEXT_LOG_DIR="${TEXT_LOG_DIR:-$NAV_WORKSPACE_DIR/log}"

# RVIZ2 screen recording
RECORD_RVIZ="${RECORD_RVIZ:-true}"
RECORD_OUTPUT_DIR="${RECORD_OUTPUT_DIR:-$NAV_WORKSPACE_DIR/videos}"
RECORD_FPS="${RECORD_FPS:-15}"
RECORD_FORMAT="${RECORD_FORMAT:-avi}"

INITIAL_POSE_X="${INITIAL_POSE_X:--9.68}"
INITIAL_POSE_Y="${INITIAL_POSE_Y:-0.55}"
INITIAL_POSE_Z="${INITIAL_POSE_Z:--0.000591}"
INITIAL_POSE_QZ="${INITIAL_POSE_QZ:-0.002345}"
INITIAL_POSE_QW="${INITIAL_POSE_QW:-0.999997}"

start_rviz_recording() {
  if [[ "${RECORD_RVIZ,,}" != "true" ]]; then
    return 0
  fi

  if ! command -v ffmpeg &>/dev/null || ! command -v xdotool &>/dev/null; then
    echo "[WARN] ffmpeg or xdotool not found, skip recording. Install: sudo apt install ffmpeg xdotool"
    return 0
  fi

  if [[ -z "${DISPLAY:-}" ]]; then
    echo "[WARN] DISPLAY is not set, skip RVIZ2 recording."
    return 0
  fi

  mkdir -p "$RECORD_OUTPUT_DIR"

  echo "[INFO] Waiting for RVIZ2 window ..."
  local rviz_window_id=""
  for i in $(seq 1 30); do
    rviz_window_id=$(xdotool search --onlyvisible --class "rviz2" 2>/dev/null | head -1)
    if [[ -z "$rviz_window_id" ]]; then
      rviz_window_id=$(xdotool search --onlyvisible --name "RViz" 2>/dev/null | head -1)
    fi
    if [[ -n "$rviz_window_id" ]]; then
      break
    fi
    sleep 1
  done

  if [[ -z "$rviz_window_id" ]]; then
    echo "[WARN] RVIZ2 window not found within 30s, skip recording."
    return 0
  fi

  eval "$(xdotool getwindowgeometry --shell "$rviz_window_id" 2>/dev/null)"
  if [[ -z "${WIDTH:-}" || -z "${HEIGHT:-}" ]]; then
    echo "[WARN] Cannot get RVIZ2 window size, skip recording."
    return 0
  fi

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local output_file="$RECORD_OUTPUT_DIR/rviz_${timestamp}.${RECORD_FORMAT}"

  echo "[INFO] Recording RVIZ2 window (${WIDTH}x${HEIGHT}) → $output_file"
  sleep 2
  ffmpeg -loglevel error -f x11grab -framerate "$RECORD_FPS" \
    -draw_mouse 0 \
    -window_id "$rviz_window_id" \
    -video_size "${WIDTH}x${HEIGHT}" \
    -i "$DISPLAY" \
    -c:v mpeg4 -q:v 5 -pix_fmt yuv420p -f "$RECORD_FORMAT" \
    "$output_file" &
  RECORD_PID=$!
}

stop_rviz_recording() {
  if [[ -n "${RECORD_PID:-}" ]] && kill -0 "$RECORD_PID" 2>/dev/null; then
    echo "[INFO] Stopping RVIZ2 recording (PID $RECORD_PID) ..."
    kill -INT "$RECORD_PID" 2>/dev/null || true
    # Give ffmpeg up to 5 seconds to finalize the file
    for i in $(seq 1 50); do
      if ! kill -0 "$RECORD_PID" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    # Force kill if still running
    if kill -0 "$RECORD_PID" 2>/dev/null; then
      kill -KILL "$RECORD_PID" 2>/dev/null || true
      wait "$RECORD_PID" 2>/dev/null || true
    fi
    echo "[INFO] Recording saved."
  fi
}

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
mkdir -p "$TEXT_LOG_DIR"
export ROS_LOG_DIR

TEXT_LOG_FILE="$TEXT_LOG_DIR/rm_serial_behavior_$(date +%Y%m%d_%H%M%S).txt"
touch "$TEXT_LOG_FILE"
echo "[INFO] rm_serial behavior logs will be saved to: $TEXT_LOG_FILE"

# ROS setup scripts may reference unset variables, so disable nounset while sourcing.
set +u
source "$ROS_SETUP_FILE"
source "$NAV_WORKSPACE_DIR/install/setup.bash"
source "$CODE_WORKSPACE_DIR/install/setup.bash"
set -u

PIDS=()

cleanup() {
  stop_rviz_recording

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
    exec "$@" \
      > >(tee >(grep --line-buffered -F "[rm_serial]: behavior=" >> "$TEXT_LOG_FILE")) \
      2> >(tee >(grep --line-buffered -F "[rm_serial]: behavior=" >> "$TEXT_LOG_FILE") >&2)
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

start_rviz_recording

echo "[INFO] Waiting 2 seconds before publishing initial pose..."
sleep 2

publish_initial_pose

launch_background "COD front tactical behavior" \
  "$CODE_WORKSPACE_DIR" \
  ros2 launch "$COD_FRONT_LAUNCH"

echo "[INFO] All launch processes started. Press Ctrl+C to stop them."
wait
