---
title: The hidden gems of moreutils
layout: post.liquid
permalink: /2023/12/19/the-hidden-gems-of-moreutils.html
---

It seems no matter how long I work with the command line, every once in a while
I find handy utilities I've never encountered before. Most people have heard
about <strike>the bird</strike> [coreutils], that's where utilities such as
`echo`, `cat`, and others come from. But did you know about [moreutils]?

[coreutils]: https://www.gnu.org/software/coreutils/
[moreutils]: https://joeyh.name/code/moreutils/

#### ts

Say I want to trace every program invocation (~*exec()*) on the system. I can do
that with `execsnoop` from the [BPF Compiler Collection].

[BPF Compiler Collection]: https://github.com/iovisor/bcc

```shell
# execsnoop
ls   1586  1401  0  /usr/bin/ls --color=auto -F
git  1587  1401  0  /usr/bin/git rev-parse ...
```

Apparently every time I touch a terminal, it runs Git to determine whether I'm
within a Git repository just so that it can show me the current branch in the
prompt. Surely that doesn't slow things down. What it doesn't show me is the
time of the invocation though. I can easily add it with `ts`.

```shell
# execsnoop | ts
Dec 19 12:39:25 ls   1791  1401  0 /usr/bin/ls --color=auto -F
Dec 19 12:39:25 git  1792  1401  0 /usr/bin/git rev-parse ...
```

I now realize that `execsnoop` does have the `-T` flag which adds invocation
times so there's no need for `ts` in this case but I've already written these
examples so yeah. `ts` can also convert time stamps into relative times. This is
especially handy when looking through log files.

```shell
$ journalctl --since yesterday --priority emerg..warning
Dec 18 19:30:47 vm sudo[5068]:  user: 3 incorrect password attempts

$ journalctl --since yesterday --priority emerg..warning | ts -r
18h7m ago vm sudo[5068]:  user: 3 incorrect password attempts
```

#### sponge

Have you ever wanted to modify a file, save the result into the same file, and
got quickly disappointed with the result?

```shell
$ echo 1\n3\n2 > file.txt
$ sort file.txt > file.txt

$ wc -l file.txt
0 file.txt # empty
```

Remember, it is the shell which is responsible for redirecting the output, not
the individual commands. In this case, when the shell sees *> file.txt*, it
opens `file.txt` for writing (or creates it if necessary). Crucially, it also
opens the file with the `O_TRUNC` flag which instantly truncates (empties) the
file. When `sort` later opens the file to do the actual work, it finds the file
empty and exits.

The most common workaround is to first redirect the output to a temporary file
and then move it back to the original name. And that's exactly what `sponge`
does behind the scenes for you.

```shell
echo 1\n3\n2 > file.txt
sort file.txt | sponge file.txt
```

Interestingly, some of the commands from `coreutils` have a "-o" flag. I could
have just written `sort -o file.txt file.txt`. Oh well.

#### vidir

This is probably what I use most often. Running `vidir` opens your `$EDITOR` or
`$VISUAL` with files / directories of the specified directory (or the current
directory) and allows you to edit them. If you change the name, it will rename
it. If you delete a file row, the file gets deleted. To delete an entire
directory with everything in it, delete its row and all sub entries.

```shell
vidir *.pdf

fd -t f | vidir -
```

What if you've made so many great changes that you want to just quit the editor
without applying any of them? You just need to quit the editor with exit code
`1`. In Vim / Helix you do that with `:cq`. This by the way works in pretty
much all cases where a command invokes your editor (e.g. when writing a commit
message).

If your distribution doesn't provide `moreutils`, there's also `qmv` from
[renameutils].

[renameutils]: https://www.nongnu.org/renameutils

#### vipe

This is a bit dirty but can be useful sometimes. Imagine you want to process a
bunch of files but cannot get the damned file name regex right and so you have
a few extra files in the output. You could just write the output to a file, edit
it, and continue from there but there a more fragile option - edit the output
right between the pipes!


```shell
fd | vipe | ...
```

In this case, the output from `fd` will be buffered by `vipe` and passed to your
configured text editor. You can make any changes you want and once you quit, the
data will be passed down the pipe if any. The downside is that if you want to
run the command again, you will need to also edit output again. It's probably a
better idea to just write it into a file. At least in this scenario.


#### pee

I'm going to mention this not because I have an actual use case for this but
just because it took me a second to realize what it actually does. `pee` takes
its stdin and passes it to all commands given as arguments. It then gathers
their output and sends that as its own output. It runs the commands using
[popen], so it's actually passing them to `/bin/sh -c` (which on most systems is
a symlink to Bash).

[popen]: https://www.man7.org/linux/man-pages/man3/popen.3.html

```shell
$ echo "Alice" | pee "xargs echo Hello" "xargs echo Hi"
Hello Alice
Hi Alice
```

I think those are all the commands I regularly use / I've used. There are  more
available, such as `chronic` (print output only if the command failed) or `ifne`
(run command only if there's non empty stdin) but I haven't needed them yet.

Besides more commands in `moreutils`, there are even more of these command sets such as [evenmoreutils] or [num-utils].

[evenmoreutils]: https://github.com/rudymatela/evenmoreutils
[num-utils]: https://suso.suso.org/programs/num-utils/index.phtml
