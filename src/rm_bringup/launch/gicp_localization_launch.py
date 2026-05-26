# Copyright (c) 2018 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os

from ament_index_python.packages import get_package_share_directory

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, GroupAction, SetEnvironmentVariable
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration, PythonExpression
from launch_ros.actions import Node
from launch_ros.descriptions import ParameterFile
from nav2_common.launch import RewrittenYaml


def generate_launch_description():
    bringup_dir = get_package_share_directory('rm_bringup')

    map_yaml_file = LaunchConfiguration('map')
    prior_pcd_file = LaunchConfiguration('prior_pcd_file')
    use_sim_time = LaunchConfiguration('use_sim_time')
    autostart = LaunchConfiguration('autostart')
    params_file = LaunchConfiguration('params_file')
    use_composition = LaunchConfiguration('use_composition')
    use_respawn = LaunchConfiguration('use_respawn')
    log_level = LaunchConfiguration('log_level')

    lifecycle_nodes = ['map_server']

    remappings = [('/tf', 'tf'),
                  ('/tf_static', 'tf_static')]

    param_substitutions = {
        'use_sim_time': use_sim_time,
        'yaml_filename': map_yaml_file}

    configured_params = ParameterFile(
        RewrittenYaml(
            source_file=params_file,
            param_rewrites=param_substitutions,
            convert_types=True),
        allow_substs=True)

    stdout_linebuf_envvar = SetEnvironmentVariable(
        'RCUTILS_LOGGING_BUFFERED_STREAM', '1')

    declare_map_yaml_cmd = DeclareLaunchArgument(
        'map',
        default_value=os.path.join(bringup_dir, 'maps', 'RMUC1.yaml'),
        description='Full path to 2D map yaml file to load for Nav2 costmaps')

    declare_prior_pcd_cmd = DeclareLaunchArgument(
        'prior_pcd_file',
        default_value=os.path.join(bringup_dir, 'maps', 'latest_scan.pcd'),
        description='Full path to prior PCD map used by GICP relocalization')

    declare_use_sim_time_cmd = DeclareLaunchArgument(
        'use_sim_time',
        default_value='false',
        description='Use simulation (Gazebo) clock if true')

    declare_params_file_cmd = DeclareLaunchArgument(
        'params_file',
        default_value=os.path.join(bringup_dir, 'params', 'singlenav2_params.yaml'),
        description='Full path to the ROS2 parameters file to use for launched nodes')

    declare_autostart_cmd = DeclareLaunchArgument(
        'autostart', default_value='true',
        description='Automatically startup the map server lifecycle node')

    declare_use_composition_cmd = DeclareLaunchArgument(
        'use_composition', default_value='False',
        description='Use composed bringup if True. GICP localization currently uses standalone nodes.')

    declare_use_respawn_cmd = DeclareLaunchArgument(
        'use_respawn', default_value='False',
        description='Whether to respawn if a node crashes.')

    declare_log_level_cmd = DeclareLaunchArgument(
        'log_level', default_value='info',
        description='log level')

    load_nodes = GroupAction(
        condition=IfCondition(PythonExpression(['not ', use_composition])),
        actions=[
            Node(
                package='nav2_map_server',
                executable='map_server',
                name='map_server',
                output='screen',
                respawn=use_respawn,
                respawn_delay=2.0,
                parameters=[configured_params],
                arguments=['--ros-args', '--log-level', log_level],
                remappings=remappings),
            Node(
                package='nav2_lifecycle_manager',
                executable='lifecycle_manager',
                name='lifecycle_manager_gicp_localization',
                output='screen',
                arguments=['--ros-args', '--log-level', log_level],
                parameters=[{'use_sim_time': use_sim_time},
                            {'autostart': autostart},
                            {'node_names': lifecycle_nodes}]),
            Node(
                package='small_gicp_relocalization',
                executable='small_gicp_relocalization_node',
                name='small_gicp_relocalization',
                output='screen',
                respawn=use_respawn,
                respawn_delay=2.0,
                parameters=[{
                    'num_threads': 4,
                    'num_neighbors': 10,
                    'max_iterations': 50,
                    'max_relocalization_iterations': 100,
                    'registration_period_ms': 2000,
                    # Keep RViz 2D Pose Estimate as a direct map->odom reset only.
                    # Set to >0 if GICP relocalization refinement should run after /initialpose.
                    'initial_pose_relax_updates': 0,
                    'global_leaf_size': 0.25,
                    'registered_leaf_size': 0.25,
                    'max_dist_sq': 1.5,
                    'relocalization_max_dist_sq': 3.0,
                    'max_fitness_score': 0.8,
                    'max_relocalization_fitness_score': 1.2,
                    'min_inlier_ratio': 0.35,
                    'min_relocalization_inlier_ratio': 0.20,
                    'max_update_distance': 1.0,
                    'max_relocalization_update_distance': 3.0,
                    'max_update_yaw': 0.52,
                    'max_relocalization_update_yaw': 1.05,
                    'constrain_2d': True,
                    'map_frame': 'map',
                    'odom_frame': 'odom',
                    'base_frame': 'base_link',
                    'robot_base_frame': 'base_link',
                    'lidar_frame': 'livox_frame',
                    'prior_pcd_file': prior_pcd_file,
                    'input_cloud_topic': '/cloud_registered',
                }],
                arguments=['--ros-args', '--log-level', log_level],
                remappings=remappings),
        ])

    ld = LaunchDescription()

    ld.add_action(stdout_linebuf_envvar)

    ld.add_action(declare_map_yaml_cmd)
    ld.add_action(declare_prior_pcd_cmd)
    ld.add_action(declare_use_sim_time_cmd)
    ld.add_action(declare_params_file_cmd)
    ld.add_action(declare_autostart_cmd)
    ld.add_action(declare_use_composition_cmd)
    ld.add_action(declare_use_respawn_cmd)
    ld.add_action(declare_log_level_cmd)

    ld.add_action(load_nodes)

    return ld
