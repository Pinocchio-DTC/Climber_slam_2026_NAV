# auto_save_map.launch.py
import os
from launch import LaunchDescription
from launch.actions import TimerAction, ExecuteProcess
from ament_index_python.packages import get_package_prefix, get_package_share_directory

def generate_launch_description():
    ld = LaunchDescription()
    bringup_dir = get_package_share_directory('rm_bringup')
    bringup_prefix = get_package_prefix('rm_bringup')
    workspace_dir = bringup_prefix.split('/install/')[0]
    source_bringup_dir = os.path.join(workspace_dir, 'src', 'rm_bringup')
    map_base_dir = source_bringup_dir if os.path.isdir(source_bringup_dir) else bringup_dir
    auto_save_dir = os.path.join(map_base_dir, 'maps', 'auto_save')
    latest_pcd_file = os.path.join(auto_save_dir, 'latest_scan.pcd')

    def create_save_command() -> list:
        script = (
            f'mkdir -p "{auto_save_dir}" && '
            'stamp=$(date +%H%M%S) && '
            f'base="{auto_save_dir}/auto_map_${{stamp}}" && '
            'ros2 run nav2_map_server map_saver_cli -f "$base" && '
            'ros2 service call /map_save std_srvs/srv/Trigger && '
            f'if [ -f "{latest_pcd_file}" ]; then cp "{latest_pcd_file}" "$base.pcd"; fi'
        )
        return [
            'bash', '-lc',
            script
        ]

    intervals = range(30, 601, 30)    # 每30秒保存一次，持续10分钟
    for t in intervals:
        action = TimerAction(
            period=float(t),
            actions=[ExecuteProcess(cmd=create_save_command(), output='screen')]
        )
        ld.add_action(action)

    return ld
