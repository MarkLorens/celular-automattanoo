class_name Nutrient
extends Area2D

## Food the player drops into the dish. Inert for now -- it sits where it lands
## and nothing consumes it yet.
##
## An Area2D rather than a body on purpose: cells swim straight through it, so
## dropping one into a crowd never shoves anybody around.
