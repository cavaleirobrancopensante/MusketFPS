extends Node
## Global settings, registered as the `Settings` autoload in project.godot.
## The main menu writes these; the battle reads them.

## Start battles in third person (over the shoulder) instead of first.
var third_person := false

## Stress test: 50 musketeers against one wave of 200 lizardmen, with an FPS
## counter, to see what your phone can handle.
var stress := false
