---
title: A few notes on find's exec
layout: post.liquid
permalink: /2024/01/02/a-few-notes-on-finds-exec.html
---

Did you know that many dynamic libraries (`*.so`) on your system are not actually
binaries but rather ASCII files?

```
$ file /usr/lib/libc.so
/usr/lib/libc.so: ASCII text

$ file -b --mime-type /usr/lib/libc.so
text/plain
```

These are called [Linker scripts], mostly used to reference other libraries,
define sections and such, but, to the great amusement of linker authors, can do
plenty of other complex things as well. Fortunately, you can usually get away
with implementing just the [basics].

[Linker scripts]: https://sourceware.org/binutils/docs/ld/Scripts.html
[basics]: https://github.com/rui314/mold/blob/fe118f634780e22107c6aab2f8fffad3eee7a69b/docs/design.md#linker-script

Anyway, how would one go about finding all dynamic libraries which are in fact
ASCII files in disguise?

Well, we have the `file` command which seems to work just fine, we just need
to hook it up to a file finding utility. Usually I would go with [fd] but
unfortunately while it does have the ability to execute a command per file, it
does not allow filtering based on the command's return code.

[fd]: https://github.com/sharkdp/fd

What about the good ol' find?

```
-exec command ;
              Execute command; true if 0 status is returned. (...)
```

The `exec` action returns true if the command returned status 0. That's exactly
what we want. As a side note, it might seem kind of weird to talk about "exec"
as "action" but `find` doesn't really accept a bunch of arguments, it accepts an
expression. It's an entire language. That's what `fd` authors mean when they say
"it does not aim to support all of find's powerful functionality".

Alright, so we just need to pass in a command which will examine the given file
and return 0 if it matches "text/plain", 1 otherwise. An inline Bash script
will do. Always does.

```
# This is wrong!
-exec bash -c '[[ $(file -b --mime-type "{}") == "text/plain" ]]' \; -print
```

The `exec` action considers everything up until `;` (or `+`) as the command,
followed by another action `-print` to actually print any matches (`-print` is
usually the default action but not when using `-exec` and a few others).

To pass the current file being examined, `-exec` will replace all occurrences
of `{}` with the file relative to the searched directory (you can also do
`-execdir` which will cd into the file's directory).

What's wrong with this? The problem is that we're literally building the shell
script by concatenating a bunch of strings. What if the file name contained some
weird characters such as quotes (or worse)? It would cause a syntax error (or
command execution). Probably not in this case, but what if!

Okay but how do we pass in the file name without string concatenation? We turn
to the Bash's manual page of course.

> If the -c option is present, then commands are read from the first non-option
argument command_string. If there are arguments after the command_string, the
first argument is assigned to $0 and any remaining arguments are assigned to
the positional parameters. The assignment to $0 sets the name of the shell,
which is used in warning and error messages.

```
$ bash -c 'echo $1' bash Hello
Hello
```

What this means is that we can rewrite the query to instead refer to the `$1`
variable and avoid interpolating the string altogether.

```
-exec bash -c '[[ $(file -b --mime-type "$1") == "text/plain" ]]' bash '{}' \; -print
```

Why put quotes around `{}`? It's probably not needed anymore, most shells leave
them intact. There was however time when Fish replaced empty brackets with an
empty string. [Fixed] in Fish [3.0.0], released Dec 28, 2018. So just in case.

[Fixed]: https://github.com/fish-shell/fish-shell/pull/4632
[3.0.0]: https://github.com/fish-shell/fish-shell/releases/tag/3.0.0

Running this on my Arch machine gives the following list:

```
$ find /usr/lib -name "*.so" -exec bash -c '[[ $(file -b --mime-type "$1") == "text/plain" ]]' bash '{}' \; -print
/usr/lib/libbsd.so
/usr/lib/libmenu.so
/usr/lib/libc.so
/usr/lib/libtic.so
/usr/lib/libpanel.so
/usr/lib/libncurses++.so
/usr/lib/libbfd.so
/usr/lib/libopcodes.so
/usr/lib/libgcc_s.so
/usr/lib/libc++.so
/usr/lib/libm.so
/usr/lib/libtinfo.so
/usr/lib/libncurses.so
/usr/lib/libform.so
/usr/lib/libcursesw.so
```

Of course there are many other ways how you can achieve the same thing. If you
don't intent to use any other filtering, you might not actually need `find`
at all and could use your shell directly. This is what it would look like in
[Nushell].

```
ls /usr/lib/**/*.so | where { (file -b --mime-type $in.name) == "text/plain" }
```

Nushell does have the ability to display mime types directly with `ls -m` but
for performance reasons it only examines the file extension, not the actual
content. I have written about Nushell [before].

[Nushell]: https://www.nushell.sh
[before]: /2023/05/25/writing-shell-scripts-in-nushell.html
