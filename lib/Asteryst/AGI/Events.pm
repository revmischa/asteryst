package Asterysk::AGI::Events;

use Exception::Class (
    'Asterysk::AGI::UserGaveCommand' => { fields => [qw( command score )] },
    'Asterysk::AGI::UserHungUp',
    'Asterysk::AGI::SpeechBackgroundFailed',
    'Asterysk::AGI::SpeechEngineNotReady' => { description => 'the SpeechCreate() application has not yet been called' },
);

1;
