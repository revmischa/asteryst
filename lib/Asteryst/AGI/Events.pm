package Asteryst::AGI::Events;

use Exception::Class (
    'Asteryst::AGI::UserGaveCommand' => { fields => [qw( command score )] },
    'Asteryst::AGI::UserHungUp',
    'Asteryst::AGI::SpeechBackgroundFailed',
    'Asteryst::AGI::SpeechEngineNotReady' => { description => 'the SpeechCreate() application has not yet been called' },
);

1;
