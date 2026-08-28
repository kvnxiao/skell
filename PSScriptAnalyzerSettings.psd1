@{
    ExcludeRules = @(
        # PowerShell 7 reads UTF-8 source without a byte order mark. The
        # decoder's elision marker is the module's only non-ASCII text.
        'PSUseBOMForUnicodeEncodedFile',

        # The module exports functions instead of cmdlets. The prompt wrapper
        # and test suite call them without Get-Help.
        'PSProvideCommentHelp'
    )
}
