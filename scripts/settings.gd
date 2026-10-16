extends Node
## Global settings, registered as the `Settings` autoload in project.godot.
## The main menu writes these; the battle reads them.

## false = 2D: Doom-style sprites and a hand-drawn first-person musket.
## true  = 3D: low-poly models with procedural animation, your own 3D body,
##         and a first/third-person camera toggle.
var use_3d := false

## 3D only: start in third person.
var third_person := false

## Stress test: 50 musketeers against one wave of 200 lizardmen, with an FPS
## counter, to see what your phone can handle.
var stress := false
