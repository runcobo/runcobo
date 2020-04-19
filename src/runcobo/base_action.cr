# All Actions should be inherited from `BaseAction`.
#
# ```
# class HelloWorld < BaseAction
#   call do
#     render_plain "Hello World!"
#   end
# end
# ```
#
# Defines Another BaseAction.
# ```
# abstract class Api::V1::BaseAction < BaseAction
# end
# ```
abstract class BaseAction < Runcobo::Action
end
