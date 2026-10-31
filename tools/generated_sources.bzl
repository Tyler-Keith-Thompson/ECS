"""Swift sources a generator writes at build time, with a checked-in copy for SwiftPM.

Bazel compiles the generator's output directly, so it never goes stale there. SwiftPM cannot run
the generator, so the published package compiles a copy kept under the module's `Generated/`
directory. `generated_swift_source` declares both halves: a genrule running `generator`, and a
test that fails when the checked-in copy differs from what the generator writes now. `just
sources` refreshes every copy.
"""

_SCRIPT = """#!/bin/sh
set -eu
if ! diff -u "$1" "$2"; then
    echo
    echo "$1 is stale (- checked in, + generated). Run \\`just sources\\` and commit it."
    exit 1
fi
"""

def _generated_source_test_impl(ctx):
    checker = ctx.actions.declare_file(ctx.label.name + ".check.sh")
    ctx.actions.write(checker, _SCRIPT, is_executable = True)
    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        runner,
        '#!/bin/sh\nexec "{}" "{}" "{}"\n'.format(checker.short_path, ctx.file.checked_in.short_path, ctx.file.generated.short_path),
        is_executable = True,
    )
    return [DefaultInfo(
        executable = runner,
        runfiles = ctx.runfiles(files = [checker, ctx.file.checked_in, ctx.file.generated]),
    )]

_generated_source_test = rule(
    implementation = _generated_source_test_impl,
    doc = "Fails when a checked-in generated source differs from the generator's output.",
    attrs = {
        "checked_in": attr.label(allow_single_file = True, mandatory = True),
        "generated": attr.label(allow_single_file = True, mandatory = True),
    },
    test = True,
)

def generated_swift_source(name, generator, tags = []):
    """`name`.swift, written by `generator`, and `name`_test, comparing it with Generated/`name`.swift.

    Args:
      name: The source's name, without `.swift`.
      generator: An executable that writes the source to standard output.
      tags: Tags for the test.
    """
    native.genrule(
        name = name,
        outs = [name + ".swift"],
        cmd = "$(execpath {}) > $@".format(generator),
        tools = [generator],
    )
    _generated_source_test(
        name = name + "_test",
        size = "small",
        checked_in = "Generated/" + name + ".swift",
        generated = ":" + name,
        tags = tags,
    )
