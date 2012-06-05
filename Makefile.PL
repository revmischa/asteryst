use inc::Module::Install;

name 'Asteryst';
all_from 'lib/Asteryst.pm';

requires 'Asterisk::FastAGI';
requires 'Profile::Log';
requires 'Config::JFDI';
requires 'Data::Visitor::Callback';
requires 'Moose' => '2.0602';
requires 'Data::Dump';
requires 'DBIx::Class::Storage::DBI::Replicated';
requires 'File::DirList';
requires 'XML::Simple';
requires 'Digest::SHA1';
requires 'MooseX::Singleton';
requires 'Quantum::Superpositions';
requires 'aliased';
requires 'Class::Autouse';
requires 'Asterisk::AGI';
requires 'Net::Server::PreFork';
requires 'Asterisk::FastAGI';  # cpan package is broken lol

WriteAll;

