class mcollective (
                    $connector               = $mcollective::params::connector_default,
                    $username                = 'mcollective',
                    $password                = 'ZnVja3RoZXN5c3RlbQo',
                    $hostname                = 'localhost',
                    $stomp_port              = $mcollective::params::stomp_port_default,
                    $psk                     = $mcollective::params::default_psk,
                    $customfactspattern      = undef,
                    $customfactsfile         = '/etc/mcollective/facts.yaml',
                    $subcollectives          = undef,
                    $ensure                  = 'installed',
                    $agent                   = true,
                    $client                  = false,
                    $plugins_packages        = [ 'package', 'service', 'puppet' ],
                    $plugins_packages_ensure = 'present',
                    $custom_plugins          = [ 'rmrf' ],
                  ) inherits mcollective::params {

  validate_string($connector)
  validate_string($username)
  validate_string($password)
  validate_string($hostname)
  validate_string($psk)

  validate_re($connector, [ '^activemq$' ], "Not a supported connector: ${connector}")

  validate_re($ensure, [ '^installed$', '^latest$' ], "Not a valid package status: ${ensure}")

  if(! $agent)
  {
    $notify_service_mcollective=undef
  }
  else
  {
    $notify_service_mcollective=Service[$mcollective::params::mcollectiveagentservice]
  }


  if($subcollectives)
  {
    validate_array($subcollectives)
  }

  Exec {
    path => '/sbin:/bin:/usr/sbin:/usr/bin',
  }

  exec { "mkdir -p ${mcollective::params::libdir} mcollective agent":
    command => "mkdir -p ${mcollective::params::libdir}/mcollective/agent",
    creates => "${mcollective::params::libdir}/mcollective/agent",
    require => Package[$mcollective::params::mcollectiveagentpackages],
  }

  if ! defined(Package['puppetlabs-release'])
  {
    package { 'puppetlabs-release':
      ensure   => 'installed',
      provider => $mcollective::params::puppetlabspackageprovider,
      source   => $mcollective::params::puppetlabspackage,
      notify   => Exec['update puppetlabs repo'],
    }
  }

  if($mcollective::params::puppetlabspackageprovider=='dpkg')
  {
    exec { 'update puppetlabs repo':
      command     => 'apt-get update',
      require     => Package['puppetlabs-release'],
      refreshonly => true,
    }
  }
  else
  {
    exec { 'update puppetlabs repo':
      command     => 'echo systemadmin.es - best blog ever',
      require     => Package['puppetlabs-release'],
      refreshonly => true,
    }
  }

  package { $mcollective::params::mcollectiveagentpackages:
    ensure  => $ensure,
    require => Exec['update puppetlabs repo'],
    notify  => $notify_service_mcollective,
  }

  if($agent)
  {

    if($plugins_packages)
    {
      $agent_plugin_packages=suffix(prefix($plugins_packages, 'mcollective-'), '-agent')
      $agent_plugin_packages_common=suffix(prefix($plugins_packages, 'mcollective-'), '-common')

      package { $agent_plugin_packages:
        ensure  => $plugins_packages_ensure,
        require => Package[$mcollective::params::mcollectiveagentpackages],
        notify  => Service[$mcollective::params::mcollectiveagentservice],
      }

      ensure_packages($agent_plugin_packages_common,
        {
          ensure  => $plugins_packages_ensure,
          require => Package[$mcollective::params::mcollectiveagentpackages],
          notify  => Service[$mcollective::params::mcollectiveagentservice],
        }
      )
    }

    #agent rmrf
    if member($custom_plugins, 'rmrf')
    {

      file { "${mcollective::params::libdir}/mcollective/agent/rmrf.rb":
        ensure   => 'present',
        owner    => 'root',
        group    => 'root',
        mode     => '0644',
        source   => "puppet:///modules/${module_name}/rmrf/rmrf.rb",
        notify   => Service[$mcollective::params::mcollectiveagentservice],
        require  => [ Exec["mkdir -p ${mcollective::params::libdir} mcollective agent"],
                      Package[$mcollective::params::mcollectiveagentpackages]],
      }

      if ! defined(File["${mcollective::params::libdir}/mcollective/agent/rmrf.ddl"])
      {
        file { "${mcollective::params::libdir}/mcollective/agent/rmrf.ddl":
          ensure   => 'present',
          owner    => 'root',
          group    => 'root',
          mode     => '0644',
          source   => "puppet:///modules/${module_name}/rmrf/rmrf.ddl",
          notify   => Service[$mcollective::params::mcollectiveagentservice],
          require  => [ Exec["mkdir -p ${mcollective::params::libdir} mcollective agent"],
                        Package[$mcollective::params::mcollectiveagentpackages]],
        }
      }

    }

    file { '/etc/mcollective/server.cfg':
      ensure  => 'present',
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      require => Package[$mcollective::params::mcollectiveagentpackages],
      notify  => Service[$mcollective::params::mcollectiveagentservice],
      content => template("${module_name}/agentconf.erb")
    }

    if($customfactspattern)
    {
      #facter -py | grep
      exec { 'customfacts':
        command => "facter -py | grep '${customfactspattern}' > ${customfactsfile}",
        notify  => Service[$mcollective::params::mcollectiveagentservice],
        require => File['/etc/mcollective/server.cfg'],
      }
    }
    else
    {
      #facter -py
      exec { 'customfacts':
        command => "facter -py > ${customfactsfile}",
        notify  => Service[$mcollective::params::mcollectiveagentservice],
        require => File['/etc/mcollective/server.cfg'],
      }
    }

    service { $mcollective::params::mcollectiveagentservice:
      ensure  => 'running',
      enable  => true,
      require => Exec['customfacts'],
    }
  }

  if($client)
  {
    if($mcollective::params::mcollectiveclientpackages!=undef)
    {
      package { $mcollective::params::mcollectiveclientpackages:
        ensure => 'installed',
      }
    }

    if(! $agent)
    {
      if member($custom_plugins, 'rmrf')
      {
        #sanity check
        if ! defined(File["${mcollective::params::libdir}/mcollective/agent/rmrf.ddl"])
        {
          file { "${mcollective::params::libdir}/mcollective/agent/rmrf.ddl":
            ensure   => 'present',
            owner    => 'root',
            group    => 'root',
            mode     => '0644',
            source   => "puppet:///modules/${module_name}/rmrf/rmrf.ddl",
            require  => Exec["mkdir -p ${mcollective::params::libdir} mcollective agent"],
          }
        }
      }
    }

    if($plugins_packages)
    {
      $client_plugin_packages=suffix(prefix($plugins_packages, 'mcollective-'), '-client')
      $client_plugin_packages_common=suffix(prefix($plugins_packages, 'mcollective-'), '-common')

      package { $client_plugin_packages:
        ensure  => $plugins_packages_ensure,
        require => Package[$mcollective::params::mcollectiveagentpackages],
      }

      ensure_packages($client_plugin_packages_common,
        {
          ensure  => $plugins_packages_ensure,
          require => Package[$mcollective::params::mcollectiveagentpackages],
          notify  => $notify_service_mcollective,
        }
      )
    }

    file { '/etc/mcollective/client.cfg':
      ensure  => 'present',
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      require => Package[$mcollective::params::mcollectiveagentpackages],
      content => template("${module_name}/clientconf.erb")
    }
  }
}
