@{
    ExcludeRules = @(
        # skell requires PowerShell 7, which reads a source file as UTF-8
        # without a byte order mark. The elision marker in the decoder is the
        # only non-ASCII text in the module.
        'PSUseBOMForUnicodeEncodedFile',

        # The module exports no cmdlets. Its functions are reachable from the
        # prompt wrapper and the test suite, neither of which reads Get-Help.
        'PSProvideCommentHelp'
    )
}
