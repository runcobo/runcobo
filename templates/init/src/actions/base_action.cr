abstract class BaseAction < Runcobo::Action
  layout "app"

  before do_something_before_action

  def do_something_before_action
    Runcobo::Log.info { "Hi! Welcome to Runcobo" }
  end
end
