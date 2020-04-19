abstract class BaseAction
  layout "runcobo"

  before set_current_user

  def set_current_user
    if rand(Int8).odd?
      Log.info "It is odd"
      # byebye
    else
      Log.info "It is even"
    end
  end
end
