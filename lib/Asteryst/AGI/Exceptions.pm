package Asteryst::AGI::Exceptions;

use Exception::Class (
    # TODO:  rename these all Asteryst::AGI::Exception::whatever.  Requires changes elsewhere in the code, obviously.
    'Asteryst::AGI::NoPathToContent'  => {
        fields       =>  [qw( content )],
        description  =>  'did not find the expected content in the database',
    },
    'Asteryst::AGI::MissingSoundFile' => {
        fields       =>  [qw( path content )],
        description  =>  'the expected content sound file did not exist, though the corresponding content data were present in the database',
    },
    'Asteryst::AGI::Exception::StreamFileFailed' => {
        fields       =>  [qw( path )],
        description  =>  q[the AGI command 'STREAM FILE' failed.  Does the file exist?  Unfortunately, I can't tell you; Asterisk::AGI's poor abstraction makes it impossible to parse differrent error conditions from the AGI output],
    },
    'Asteryst::AGI::Exception::WaitForDigitFailed' => {
        description  => q[the AGI command 'WAIT FOR DIGIT' failed (i.e. gave a -1 response)],
    },
    'Asteryst::AGI::Exception::UnreachableCodeReached' => {
        description  => q[we reached a point in the code that a programmer marked unreachable.  This should never happen.  Look at the code and see what's wrong],
    },
);

1;
