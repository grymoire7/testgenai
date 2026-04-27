module Testgenai
  module Scanner
    class Base
      def scan
        raise NotImplementedError, "#{self.class} must implement #scan"
      end
    end
  end
end
