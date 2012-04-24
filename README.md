asteryst
========

Asterisk FastAGI application framework. Supports speech API and method dispatch based on FastAGI requests.

Asterysk is designed to do for voice applications what Catalyst does for web applications, with a similar interface and structure.


## Usage

Many prompt file paths are currently hard-coded. You'll probably want to make your sound files reflect these, or change them.

You will need to create a config file, `asteryst.yml`. See `sample_asteryst.yml`

If you do actually wish to use this code, please drop us a line. There are pieces that will need filling in, since this was once a part of a larger codebase.


## Purpose

The main purpose of this library is to facilitate the rapid development of IVR (interactive voice-response) voice applications with Asterisk.

In particular, there are many unplesant aspects of developing said class of application:

* FastAGI interface:
  + Has lots of hidden surprises and issues lurking
  + Screws with STDOUT/STDERR
  + Bizzare and inconsistant function names, params and return types
  + Incorrect and misleading Asterisk::FastAGI documentation
  + No standard way of dispatching from a request to a Perl controller/method
* Speech API:
  + Need to keep track of which grammar context you are in
  + API documentation is greatly lacking
* Audio file playback:
  + Simplifies playing back prompts, in particular getting speech and DTMF input while playing a file
  + Supports resuming playback from a given point in a file (see `Jumpfile`)
  + Can fetch (and cache) files to play from a URL
  + See `Prompt` and `UserInput` controllers
* Voice ads:
  + Support for Apptera and VoodooVox ad platforms

In short, a lot of the hard work has already been done for you. We suffered for many months to debug and interface with the sketchy APIs provided by Asterisk, and we would like to save others the effort.


## History

Asteryst was a library developed for a very powerful and robust voice application by contract developers Mischa Spiegelmock and Quinn Weaver. Despite the considerable savings attained from moving from an expensive VXML provider to Asterisk in THE CLOUD, the company no longer exists. However, the developers wanted the code to be released to the open source community.

