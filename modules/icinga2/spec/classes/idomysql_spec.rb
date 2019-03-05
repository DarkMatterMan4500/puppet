require 'spec_helper'

describe('icinga2::feature::idomysql', :type => :class) do
  let(:pre_condition) do
    [
      "class { 'icinga2': features => [], constants => {'NodeName' => 'host.example.org'} }"
    ]
  end

  on_supported_os.each do |os, facts|
   context "on #{os}" do
     let(:facts) do
        case facts[:kernel]
        when 'windows'
          facts.merge({
            :icinga2_puppet_hostcert => 'C:/ProgramData/PuppetLabs/puppet/ssl/certs/host.example.org.pem',
            :icinga2_puppet_hostprivkey => 'C:/ProgramData/PuppetLabs/puppet/ssl/private_keys/host.example.org.pem',
            :icinga2_puppet_localcacert => 'C:/ProgramData/PuppetLabs/var/lib/puppet/ssl/certs/ca.pem',
          })
        else
          facts.merge({
            :icinga2_puppet_hostcert => '/etc/puppetlabs/puppet/ssl/certs/host.example.org.pem',
            :icinga2_puppet_hostprivkey => '/etc/puppetlabs/puppet/ssl/private_keys/host.example.org.pem',
            :icinga2_puppet_localcacert => '/etc/lib/puppetlabs/puppet/ssl/certs/ca.pem',
          })
        end
      end

      before(:each) do
        case facts[:kernel]
        when 'windows'
          @icinga2_conf_dir = 'C:/ProgramData/icinga2/etc/icinga2'
          @icinga2_pki_dir = 'C:/ProgramData/icinga2/var/lib/icinga2/certs'
          @ido_mysql_schema_dir = 'C:/Program Files/icinga2/usr/share/icinga2-ido-mysql/schema'
          @icinga2_sslkey_mode = nil
          @icinga2_user = nil
          @icinga2_group = nil
        when 'FreeBSD'
          @icinga2_conf_dir = '/usr/local/etc/icinga2'
          @icinga2_pki_dir = '/var/lib/icinga2/certs'
          @ido_mysql_schema_dir = '/usr/local/share/icinga2-ido-mysql/schema'
          @icinga2_sslkey_mode = '0600'
          @icinga2_user = 'icinga'
          @icinga2_group = 'icinga'
        else
          @icinga2_conf_dir = '/etc/icinga2'
          @icinga2_pki_dir = '/var/lib/icinga2/certs'
          @ido_mysql_schema_dir = '/usr/share/icinga2-ido-mysql/schema'
          @icinga2_sslkey_mode = '0600'
          case facts[:osfamily]
          when 'Debian'
            @icinga2_user = 'nagios'
            @icinga2_group = 'nagios'
          else
            @icinga2_user = 'icinga'
            @icinga2_group = 'icinga'
          end
        end
      end

      context "with defaults" do
        let(:params) do
          {
            :password => 'foo'
          }
        end

        if facts[:kernel] == 'Linux'
          it { is_expected.to contain_package('icinga2-ido-mysql').with({ 'ensure' => 'installed' }) }
        end

        it { is_expected.to contain_icinga2__feature('ido-mysql').with({'ensure' => 'present'}) }

        it { is_expected.to contain_icinga2__object('icinga2::object::IdoMysqlConnection::ido-mysql')
          .with({ 'target' => "#{@icinga2_conf_dir}/features-available/ido-mysql.conf" })
          .that_notifies('Class[icinga2::service]') }

        it { is_expected.to contain_concat__fragment('icinga2::feature::ido-mysql')
          .with({
            'target' => "#{@icinga2_conf_dir}/features-available/ido-mysql.conf",
            'order'  => '05', })
          .with_content(/library \"db_ido_mysql\"$/) }
      end

      context "with ensure => absent" do
        let(:params) do
          {
            :ensure   => 'absent',
            :password => 'foo'
          }
        end

        it { is_expected.to contain_icinga2__feature('ido-mysql').with({'ensure' => 'absent'}) }
      end

      context "with import_schema => true" do
        let(:params) do
          {
            :import_schema => true,
            :password      => 'foo'
          }
        end

        it { is_expected.to contain_exec('idomysql-import-schema')
          .with({
            'user'    => 'root',
            'command' => "mysql -u icinga -p'foo' icinga < #{@ido_mysql_schema_dir}/mysql.sql", }) }
      end

      if facts[:kernel] == 'Linux'
        context "with icinga2::manage_package => false" do
          let(:params) do
            {
              :password => 'foo'
            }
          end

          let(:pre_condition) do
            [
              "class { 'icinga2': features => [], manage_package => false }"
            ]
          end

          it { should_not contain_package('icinga2').with({ 'ensure' => 'installed' }) }
          it { should_not contain_package('icinga2-ido-mysql').with({ 'ensure' => 'installed' }) }
        end
      end

      context "with enable_ssl => true, host => 127.0.0.1, port => 3306, import_schema => true, ssl_key => foo, ssl_cert => bar, ssl_cacert => baz" do
        let(:params) do
          {
            :enable_ssl    => true,
            :ssl_key       => 'foo',
            :ssl_cert      => 'bar',
            :ssl_cacert    => 'baz',
            :host          => '127.0.0.1',
            :port          => 3306,
            :import_schema => true,
            :password      => 'foo'
          }
        end

        it { is_expected.to contain_file("#{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql.key")
          .with({
            'mode'  => @icinga2_sslkey_mode,
            'owner' => @icinga2_user,
            'group' => @icinga2_group, })
          .with_content(/^foo/) }

        it { is_expected.to contain_file("#{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql.crt")
          .with({
            'owner' => @icinga2_user,
            'group' => @icinga2_group, })
          .with_content(/^bar$/) }

        it { is_expected.to contain_file("#{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql_ca.crt")
          .with({
            'owner' => @icinga2_user,
            'group' => @icinga2_group, })
          .with_content(/^baz$/) }

        it { is_expected.to contain_exec('idomysql-import-schema')
          .with({
            'user'    => 'root',
            'command' => "mysql -h 127.0.0.1 -P 3306 -u icinga -p'foo' --ssl-ca #{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql_ca.crt --ssl-cert #{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql.crt --ssl-key #{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql.key icinga < #{@ido_mysql_schema_dir}/mysql.sql", }) }
      end

      context "with enable_ssl => true, import_schema => true, ssl_key_path, ssl_cert_path and ssl_cacert_path set" do
        let(:params) do
          {
            :enable_ssl      => true,
            :ssl_key_path    => "#{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql.key",
            :ssl_cert_path   => "#{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql.crt",
            :ssl_cacert_path => "#{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql_ca.crt",
            :import_schema   => true,
            :password        => 'foo'
          }
        end

        it { is_expected.to contain_concat__fragment('icinga2::object::IdoMysqlConnection::ido-mysql')
          .with_content %r{ssl_key = "#{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql.key"} }

        it { is_expected.to contain_concat__fragment('icinga2::object::IdoMysqlConnection::ido-mysql')
          .with_content %r{ssl_cert = "#{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql.crt"} }

        it { is_expected.to contain_concat__fragment('icinga2::object::IdoMysqlConnection::ido-mysql')
          .with_content %r{ssl_ca = "#{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql_ca.crt"} }

        it { is_expected.to contain_exec('idomysql-import-schema')
          .with({
            'user'    => 'root',
            'command' => "mysql -u icinga -p'foo' --ssl-ca #{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql_ca.crt --ssl-cert #{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql.crt --ssl-key #{@icinga2_pki_dir}/IdoMysqlConnection_ido-mysql.key icinga < #{@ido_mysql_schema_dir}/mysql.sql", }) }
      end
    end

  end
end