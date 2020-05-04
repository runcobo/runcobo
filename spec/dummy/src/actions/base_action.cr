abstract class BaseAction
  layout "runcobo"

  before set_current_user

  def set_current_user
    if rand(Int8).odd?
      Runcobo::Log.info { "It is odd" }
    else
      Runcobo::Log.info { "It is even" }
    end
  end
end
