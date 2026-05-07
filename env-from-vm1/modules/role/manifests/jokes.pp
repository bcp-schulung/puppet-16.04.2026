#
class role::jokes {
}

#
class role::jokes::frontend inherits role::jokes {
}

#
class role::jokes::postgres inherits role::jokes {
  class { 'profile::postgres':
    database => lookup('jokes::database'),
  }
}

#
class role::jokes::backend inherits role::jokes {
  class { 'profile::backend':
    database => lookup('jokes::database'),
  }
}

#
class role::jokes::allinone inherits role::jokes {
  #include profile::frontend
  class { 'profile::postgres':
    database => lookup('jokes::database'),
  }
  class { 'profile::backend':
    database => lookup('jokes::database'),
  }
}
