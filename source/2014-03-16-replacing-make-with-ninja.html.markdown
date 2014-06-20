---
title: Replacing Make with Ninja
date: 2014-03-16 16:00 UTC
tags: ninja, make, build tools
layout: post
author: Jiri Pospisil
---
Make and all of its flavours have been here for almost 40 years and it's a tool
hard to beat for many things. There are however cases when you do not need the
power of Make and are willing to trade the flexibility for something else. In
case of [Ninja](http://martine.github.io/ninja), for its speed.

Speed is the main motivation behind Ninja and its decisions how to write your
build files. Ninja was written by [Evan Martin](http://neugierig.org)
specifically to fight slow build cycles while working on Google Chrome. 

The bigger the project, the longer it takes to figure out what files need to be
recompiled or if any action is required at all. As a result of numerous
optimizations, Ninja is much faster when compared to alternatives.  Ninja's
secret is to do the least amount of work possible and let other more high level
tools to handle the rest upfront. 

READMORE

Let's see an example of a simple script featuring all of the abstractions Ninja
provides:

```bash
# build.ninja
cc     = clang
cflags = -Weverything

rule compile
  command = $cc $cflags -c $in -o $out

rule link
  command = $cc $in -o $out

build hello.o: compile hello.c
build hello: link hello.o

default hello
```

Putting aside the fact that there's no point in writing something like this for
a single file, let's see what's going on there. First, we define 2 variables and
later refer to them using the `$` sign. Second, there are rules. Rules are
essentially functions that call an external command to perform an action.
Finally, build statements are used to define dependencies between input and
output files. If you were to write the same with Make using its conventions,
you'd probably end up with something like
[this](https://gist.github.com/mekishizufu/5f0750989c2cefc0e257).

To see a more realistic example with proper dependency tracking, I converted
[libgit2](http://libgit2.github.com)'s
[Makefile.embed](https://github.com/libgit2/libgit2/blob/2b403/Makefile.embed)
to Ninja. The Makefile compiles libgit2 and creates a static library out of it.
You can see the result
[here](https://gist.github.com/mekishizufu/1d099dda373280206aee).

You've probably noticed a few things. First, Ninja scripts are explicit. You
cannot use any fancy substitution/wildcard functions (or any other control
structures for that matter). As a result, the script is not only much longer but
it also cannot handle any conditions making it unsuitable to any multi
platform/compiler development. And this is by design.

I've mentioned that Ninja is meant to be used with a higher level tool
(generator). One of the reasons for doing that is to overcome the said issues.
In practice this means that you do not care about the absence of conditions or
any other capabilities because the generator handles it for you simply by
generating a different set of build scripts.

Ninja comes with a simple [Python based
generator](https://github.com/martine/ninja/blob/84986/misc/ninja_syntax.py).
The generator is straightforward, you call the methods and it outputs the
corresponding Ninja syntax to a file. Since it's just Python, you can make all
of the platform and compiler decisions here. In fact, this is the way Ninja
itself is [built](https://github.com/martine/ninja/blob/84986/configure.py):

```python
from ninja_syntax import Writer

with open("build.ninja", "w") as buildfile:
    n = Writer(buildfile)

    if platform.is_msvc():
        n.rule("link",
                command="$cxx $in $libs /nologo /link $ldflags /out:$out",
                description="LINK $out")
    else:
        n.rule("link",
                command="$cxx $ldflags -o $out $in $libs",
                description="LINK $out")
```

The fun part is that Ninja is already supported by some of the most popular meta
build systems out there - [CMake](http://www.cmake.org) and
[Gyp](https://code.google.com/p/gyp). If you have a CMake based project and
assuming you have Ninja available in your PATH, all you need to do is to choose
Ninja as the
[generator](http://www.cmake.org/cmake/help/v2.8.12/cmake.html#section_Generators):

```bash
$ cd libgit2 && mkdir build && cd build
$ cmake -GNinja ..
$ ninja
```

With this change, CMake generates a bunch of Ninja build files and Ninja builds
the project. Notice that there's no need to specify the number of parallel jobs
(`-j [jobs]`) because Ninja automatically chooses the value based on the number
of cores available. 

The compilation speed is not very different although it might be a bit faster
due to Ninja consuming very little CPU while driving the build process. What is
however very significant are the time savings when working with the source code
and invoking the build process again. A non-scientific benchmark performed on my laptop
shows that Ninja is indeed much faster:

<table class="table table-hover">
  <thead>
    <th></th>
    <th></th>
    <th>No file changes</th>
    <th>1 file change</th>
  </thead>
  <tbody>
    <tr>
      <td></td>
      <td><strong>Make</strong></td>
      <td>0.670s</td>
      <td>2.404s</td>
    </tr>
    <tr>
      <td></td>
      <td><strong>Ninja</strong></td>
      <td>0.041s</td>
      <td>0.761s</td>
    </tr>
  </tbody>
</table>

These savings will become even more significant as your project grows. I
encourage you to try [Ninja](https://github.com/martine/ninja) and compare the
build cycle times with Make. You will very likely see a similar difference. If
you want to learn more about Ninja, here's a few links:

- [Ninja, a small build system with a focus on speed](http://martine.github.io/ninja) (homepage)
- [The Performance of Open Source Software | Ninja](http://www.aosabook.org/en/posa/ninja.html)
- [Ninja, a new build system](http://neugierig.org/software/chromium/notes/2011/02/ninja.html)
