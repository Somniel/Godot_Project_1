class_name ItemData
extends Resource
## Defines an item type's static properties for the inventory system.

## Unique identifier for this item type (e.g., &"pearl")
@export var id: StringName = &""

## Display name shown in UI (e.g., "Pearl")
@export var display_name: String = ""

## Description shown in tooltips
@export var description: String = ""

## Icon texture for inventory slots (recommended 64x64)
@export var icon: Texture2D = null

## Maximum stack size (1 = non-stackable)
@export var max_stack: int = 99

## Scene to instantiate when item is dropped in world
@export var world_scene: PackedScene = null

## Interaction verb for pickup prompt (e.g., "Grab")
@export var interaction_type: String = "Grab"

## Whether the world item emits light
@export var is_glowing: bool = false

## Glow light color (only used if is_glowing is true)
@export var glow_color: Color = Color.WHITE

## Glow light energy/intensity (only used if is_glowing is true)
@export var glow_energy: float = 0.8

## Glow light range in units (only used if is_glowing is true)
@export var glow_range: float = 2.5
