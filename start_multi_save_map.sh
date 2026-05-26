#!/usr/bin/env bash
set -euo pipefail

NAV_WORKSPACE_DIR="/home/nucshao/Climber_slam_2026_NAV"
CODE_WORKSPACE_DIR="/home/nucshao/Climber_slam_2026_code"

MID360_LAUNCH="$NAV_WORKSPACE_DIR/src/livox_ros_driver2/launch_ROS2/rviz_MID360_launch.py"
MULTIPLE_NAV_LAUNCH="$NAV_WORKSPACE_DIR/src/rm_bringup/launch/multiplenav_launch.py"
COD_SAVE_MAP_LAUNCH="$CODE_WORKSPACE_DIR/COD_Behavior/launch/cod_save_map.launch.py"

ROS_SETUP_FILE="${ROS_SETUP_FILE:-/opt/ros/humble/setup.bash}"
ROS_LOG_DIR="${ROS_LOG_DIR:-/tmp/ros_logs}"
INITIAL_POSE_X="${INITIAL_POSE_X:--10.0}"
INITIAL_POSE_Y="${INITIAL_POSE_Y:-0.37}"
INITIAL_POSE_Z="${INITIAL_POSE_Z:-0.0}"
INITIAL_POSE_QZ="${INITIAL_POSE_QZ:-0.002345}"
INITIAL_POSE_QW="${INITIAL_POSE_QW:-0.999997}"
INITIAL_POSE_WAIT_SECONDS="${INITIAL_POSE_WAIT_SECONDS:-30}"
INITIAL_POSE_PUBLISH_TIMES="${INITIAL_POSE_PUBLISH_TIMES:-10}"
SKIP_EXISTING_PROCESS_CHECK="${SKIP_EXISTING_PROCESS_CHECK:-0}"

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
check_file "$MID360_LAUNCH"
check_file "$MULTIPLE_NAV_LAUNCH"
check_file "$COD_SAVE_MAP_LAUNCH"

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

check_no_existing_stack_processes() {
  if [[ "$SKIP_EXISTING_PROCESS_CHECK" == "1" ]]; then
    return 0
  fi

  local existing
  existing="$(ps -eo pid=,cmd= | grep -E \
    'nav2_controller/controller_server|nav2_planner/planner_server|nav2_bt_navigator/bt_navigator|nav2_lifecycle_manager/lifecycle_manager|nav2_waypoint_follower/waypoint_follower|nav2_velocity_smoother/velocity_smoother|small_point_lio_node|async_slam_toolbox_node|livox_ros_driver2_node|cod_behavior|rm_serial' \
    | grep -v grep || true)"

  if [[ -n "$existing" ]]; then
    echo "[ERROR] Existing ROS/Nav2 stack processes are still running:"
    echo "$existing"
    echo "[HINT] Stop the old launch first, or run with SKIP_EXISTING_PROCESS_CHECK=1 if this is intentional."
    exit 1
  fi
}

publish_initial_pose() {
  echo "[INFO] Waiting up to ${INITIAL_POSE_WAIT_SECONDS}s for /initialpose subscriber..."
  local waited=0
  local subscribers=0
  while (( waited < INITIAL_POSE_WAIT_SECONDS )); do
    subscribers="$(ros2 topic info /initialpose 2>/dev/null | awk '/Subscription count:/ {print $3}')"
    subscribers="${subscribers:-0}"
    if (( subscribers > 0 )); then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  if (( subscribers == 0 )); then
    echo "[WARN] No /initialpose subscriber found; skipping topic initial pose publish."
    return 0
  fi

  echo "[INFO] Publishing initial pose on /initialpose..."
  ros2 topic pub --times "$INITIAL_POSE_PUBLISH_TIMES" --rate 5 --wait-matching-subscriptions 1 \
    /initialpose geometry_msgs/msg/PoseWithCovarianceStamped \
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

check_no_existing_stack_processes

launch_background "Livox MID360 driver" \
  "$NAV_WORKSPACE_DIR" \
  ros2 launch "$MID360_LAUNCH"

launch_background "rm_bringup multiple nav" \
  "$NAV_WORKSPACE_DIR" \
  ros2 launch "$MULTIPLE_NAV_LAUNCH"

publish_initial_pose

launch_background "COD save map behavior" \
  "$CODE_WORKSPACE_DIR" \
  ros2 launch "$COD_SAVE_MAP_LAUNCH"

echo "[INFO] All launch processes started. Press Ctrl+C to stop them."
wait
