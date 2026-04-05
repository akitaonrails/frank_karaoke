Frank Karaoke will be a Flutter app (desktop linux/Android smartphone and tablet).

Most karaoke businesses of the past uses some Asian "karaoke box" with pre-defined sets of karaoke music. But they are either obsolete or in korean, chinese, japanese and difficult to read and operate.

Many modern karaoke business end up allowing chromecast-like features so users can cast YouTube and find their most recent favorite songs from there.

But there is a small downgrade in that approach: one of the fun things in a karaoke is the singing scoring systems. So if you use youtube, you can find your favorite song easily, but you can't enjoy the scoring with your friends or create competitions for the best scores.

So the idea of Frank Karaoke is to be a "wrapper" over YouTube: find any song you like, but you can overlay it with a real-time audio analyzer that listens to the people singing (1 or more) and provides a score (need to research what is the best way to score singing, if it's matching the peak frequencies from the microphone and the youtube audio). Then provide a score, a simple session history with every past song with the scores. easy way to maybe add the people in the group for the evening session and attribute each song for some one. I think we can just show youtube's own web interface and it's own queuing system.

The wrapper app provides access to this overlay with real-time audio scoring (think of real-time visualizations that can make the singing more enjoyable without hiding the videos undernath - which will most like contain the lyrics).

The wrapper app needs to have casting abilities to stream to a chromecast. and bluetooth support from the phone so it can connect to external speakers (which will also probably have the microphones - check how JBL karaoke boxes work, if the audio goes directly to the speaker and if the smartphone/tablet can hear it, research first the most popular jbl karaoke available in brazil).

This app must be built with Flutter, properly configured to compile both desktop and tablet/smartphone versions. the desktop version will be used so I can easily test while we implement it.

It has to be very simple to use, no need to put too much advanced controls. Intuitive for non tech users, big action buttons, big numbers/scoring/names, pretty, modern. Overlay maybe have a toggle of sorts. 

It would be great if the audio output from the app (which will hijack from the youtube webapp) can also have controle for pitch/tone so it makes it easier to sing difficult high pitch songs.

Plan and let me know what you think.
