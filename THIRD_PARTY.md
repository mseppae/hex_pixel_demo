# Third-party components

This project links two libraries. Neither is included in this repository; both
come with the Odin compiler.

## raylib — zlib/libpng license

The game uses raylib through Odin's `vendor:raylib` binding. raylib is
copyright (c) 2013-2025 Ramon Santamaria (@raysan5) and is distributed under
the zlib/libpng license. If you distribute compiled builds of this game, that
license requires you to include its notice:

> This software is provided "as-is", without any express or implied warranty.
> In no event will the authors be held liable for any damages arising from the
> use of this software.
>
> Permission is granted to anyone to use this software for any purpose,
> including commercial applications, and to alter it and redistribute it
> freely, subject to the following restrictions:
>
> 1. The origin of this software must not be misrepresented; you must not
>    claim that you wrote the original software. If you use this software in a
>    product, an acknowledgment in the product documentation would be
>    appreciated but is not required.
> 2. Altered source versions must be plainly marked as such, and must not be
>    misrepresented as being the original software.
> 3. This notice may not be removed or altered from any source distribution.

Full text: https://github.com/raysan5/raylib/blob/master/LICENSE

## Odin — BSD-3-Clause

The Odin programming language and its core and vendor libraries are copyright
(c) 2016-2025 Ginger Bill and contributors, under the BSD-3-Clause license.
Programs compiled with Odin carry no license obligations from the compiler
itself.

Full text: https://github.com/odin-lang/Odin/blob/master/LICENSE

## Asset generator scripts

The scripts in `art_source/` run only on your own machine to produce the PNG
and WAV files in `assets/`. They use numpy, scipy and Pillow (BSD and MIT-CMU
licenses). Nothing from those libraries ends up in the game.

## Assets

Every image and sound in `assets/` was generated for this project by the
scripts in `art_source/`. None of it is taken from an existing tileset, sprite
pack or sound library. They are covered by this project's MIT license.
