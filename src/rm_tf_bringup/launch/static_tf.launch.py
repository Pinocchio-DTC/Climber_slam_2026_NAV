import os

import yaml

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def _create_publishers(context):
    config_file = LaunchConfiguration('config_file').perform(context)
    with open(config_file, 'r', encoding='utf-8') as stream:
        config = yaml.safe_load(stream) or {}

    transforms = config.get('transforms', [])
    if not isinstance(transforms, list):
        raise RuntimeError("'transforms' in TF config must be a list")

    publishers = []
    child_frames = set()
    for index, transform in enumerate(transforms):
        name = transform.get('name', f'static_tf_{index}')
        parent = transform['parent_frame']
        child = transform['child_frame']
        translation = transform.get('translation', [0.0, 0.0, 0.0])
        rotation = transform.get('rotation_rpy', [0.0, 0.0, 0.0])

        if len(translation) != 3 or len(rotation) != 3:
            raise RuntimeError(
                f"Transform '{name}' requires three translation and three rotation_rpy values")
        if parent == child:
            raise RuntimeError(f"Transform '{name}' has identical parent and child frames")
        if child in child_frames:
            raise RuntimeError(f"Child frame '{child}' is configured more than once")
        child_frames.add(child)

        publishers.append(Node(
            package='tf2_ros',
            executable='static_transform_publisher',
            name=name,
            output='screen',
            arguments=[
                '--x', str(translation[0]),
                '--y', str(translation[1]),
                '--z', str(translation[2]),
                '--roll', str(rotation[0]),
                '--pitch', str(rotation[1]),
                '--yaw', str(rotation[2]),
                '--frame-id', str(parent),
                '--child-frame-id', str(child),
            ],
        ))

    return publishers


def generate_launch_description():
    default_config = os.path.join(
        get_package_share_directory('rm_tf_bringup'),
        'config',
        'static_transforms.yaml',
    )

    return LaunchDescription([
        DeclareLaunchArgument(
            'config_file',
            default_value=default_config,
            description='YAML file containing the static transform list.',
        ),
        OpaqueFunction(function=_create_publishers),
    ])
