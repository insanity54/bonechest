# bonechest

Minetest mod designed to dis-incentivize player killing and common griefer/troll patterns. Made by admins for admins.

## Features

  * [x] Disables default bones mod register_on_dieplayer callback
  * [x] A bonechest captures a player's items when they die.
  * [x] A bonechest surrenders it's contents only to the player who spawned the bonechest.
  * [x] A bonechest does not give players a free item (such as bones).
  * [x] A bonechest refuses to be created in a protected area.
  * [x] A bonechest destroys itself when it is emptied.
  * [x] A bonechest destroys itself after 7 days (configurable using `bonechest_destroy_time`)
  * [x] A bonechest creates a record of the destroyed bonechest in mod storage
    * [x] When a bonechest is created (or not, due to destroy mode), record the items
    * [x] When a bonechest is modified, record the changed items
    * [x] When a bonechest is destroyed due to being empty, destroy the record

## Authors of source code

Originally by PilzAdam (MIT)
Various Minetest developers and contributors (MIT)
Modified features by @insanity54 (Unlicense)

## Authors of media (textures)

All textures: paramat (CC BY-SA 3.0)


