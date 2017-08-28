require "dim"

class ConsoleAppender
end

class Logger
  attr_accessor :appender
end

class MockDB
end

class RealDB
  attr_accessor :username, :password
  def initialize(username, password)
    @username, @password = username, password
  end
end

class App
  attr_accessor :logger, :db
  def initialize(logger=nil)
    @logger = logger
  end
end

describe Dim::Container do
  let(:container) { Dim::Container.new }

  context "creating objects" do
    before { container.register(:app) { App.new } }
    specify { expect(container.app).to be_a(App) }
  end

  context "returning the same object every time" do
    let(:app) { container.app }
    before { container.register(:app) { App.new } }
    specify { expect(container.app).to be(app) }
  end

  context "overriding previously-registered objects" do
    before do
      container.register(:some_value) { "A" }
      container.override(:some_value) { "B" }
    end

    specify { expect(container.some_value).to eq("B") }
  end

  context "explicitly clearing cache" do
    before do 
      container.register(:app) { App.new } 
    end

    specify "returns new object" do
      expect { 
        container.clear_cache! }.
        to change { container.app }
    end
  end

  context "contructing dependent objects" do
    let(:app) { container.app }

    before do
      container.register(:app) { |c| App.new(c.logger) }
      container.register(:logger) { Logger.new }
    end

    specify { expect(app.logger).to be(container.logger) }
  end

  context "constructing dependent objects with setters" do
    let(:app) { container.app }

    before do
      container.register(:app) do |c|
        App.new.tap { |obj| obj.db = c.database }
      end
      container.register(:database) { MockDB.new }
    end

    specify { expect(app.db).to be(container.database) }
  end

  context "constructing multiple dependent objects" do
    let(:app) { container.app }

    before do
      container.register(:app) do |c|
        App.new(c.logger).tap { |obj| obj.db = c.database }
      end
      container.register(:logger) { Logger.new }
      container.register(:database) { MockDB.new }
    end

    specify { expect(app.logger).to be(container.logger) }
    specify { expect(app.db).to be(container.database) }
  end

  context "constructing chains of dependencies" do
    let(:logger) { container.app.logger }

    before do
      container.register(:app) { |c| App.new(c.logger) }
      container.register(:logger) do |c|
        Logger.new.tap { |obj| obj.appender = c.logger_appender }
      end
      container.register(:logger_appender) { ConsoleAppender.new }
      container.register(:database) { MockDB.new }
    end

    specify { expect(logger.appender).to be(container.logger_appender) }
  end

  context "constructing literals" do
    let(:db) { container.database }

    before do
      container.register(:database) { |c| RealDB.new(c.username, c.userpassword) }
      container.register(:username) { "user_name_value" }
      container.register(:userpassword) { "password_value" }
    end

    specify { expect(db.username).to eq("user_name_value") }
    specify { expect(db.password).to eq("password_value") }
  end

  describe "Errors" do
    specify "raise missing service error" do
      expect {
        container.undefined_service_name
      }.to raise_error(Dim::MissingServiceError, /undefined_service_name/)
    end

    context "duplicate service names" do
      before { container.register(:duplicate_name) { 0 } }

      specify do
        expect {
          container.register(:duplicate_name) { 0 }
        }.to raise_error(Dim::DuplicateServiceError, /duplicate_name/)
      end
    end
  end

  describe "Parent/Child Container Interaction" do
    let(:parent) { container }
    let(:child) { Dim::Container.new(parent) }

    before do
      parent.register(:cell) { :parent_cell }
      parent.register(:gene) { :parent_gene }
      child.register(:gene) { :child_gene }
    end

    context "reusing a service from the parent" do
      specify { expect(child.cell).to eq(:parent_cell) }
    end

    context "overiding a service from the parent" do
      specify "the child service overrides the parent" do
        expect(child.gene).to eq(:child_gene)
      end
    end

    context "wrapping a service from a parent" do
      before { child.register(:cell) { |c| [c.parent.cell] } }
      specify { expect(child.cell).to eq([:parent_cell]) }
    end

    context "overriding an indirect dependency" do
      before do
        parent.register(:wrapped_cell) { |c| [c.cell] }
        child.register(:cell) { :child_cell }
      end

      specify { expect(child.wrapped_cell).to eq([:child_cell]) }
    end

    context "parent / child service conflicts from parents view" do
      specify { expect(parent.gene).to eq(:parent_gene) }
    end

    context "child / child service name conflicts" do
      let(:other_child) { Dim::Container.new(parent) }

      before { other_child.register(:gene) { :other_child_gene } }

      specify { expect(child.gene).to eq(:child_gene) }
      specify { expect(other_child.gene).to eq(:other_child_gene) }
    end
  end

  describe "Registering env variables" do
    context "which exist in ENV" do
      before do
        ENV["SHAZ"] = "bot"
        container.register_env(:shaz)
      end

      specify { expect(container.shaz).to eq("bot") }
    end

    context "which only exist in parent" do
      let(:parent) { container }
      let(:child) { Dim::Container.new(parent) }

      before do
        parent.register(:foo) { "bar" }
        ENV["FOO"] = nil
        child.register_env(:foo)
      end

      specify { expect(container.foo).to eq("bar") }
    end

    context "which don't exist in ENV but have a default" do
      before { container.register_env(:abc,"123") }
      specify { expect(container.abc).to eq("123") }
    end

    context "which don't exist in optional hash" do
      specify do
        expect {
          container.register_env(:dont_exist_in_env_or_optional_hash)
        }.to raise_error(Dim::EnvironmentVariableNotFound)
      end
    end
  end

  context "verifying dependencies" do
    before { container.register(:app) { :app } }

    specify { expect(container.verify_dependencies(:app)).to be true }
    specify { expect(container.verify_dependencies(:app,:frobosh)).to be false }
  end

  context "check if service exists" do
    before do
      container.register(:app) { :app }
      def container.custom_method; end
    end

    specify { expect(container.service_exists?(:app)).to be true }
    specify { expect(container.service_exists?(:custom_method)).to be true }
    specify { expect(container.service_exists?(:missing_app)).to be false }
  end

  context "dangerously verifying dependencies" do
    before { container.register(:app) { :app } }

    specify { expect(container.verify_dependencies!(:app)).to be_nil }

    specify "raise error with list of missing services" do
      expect{ container.verify_dependencies!(:app,:missing_app) }.to raise_error(Dim::MissingServiceError,/missing_app/)
    end
  end
end
