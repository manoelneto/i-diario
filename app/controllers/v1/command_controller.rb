module V1
  class CommandController < Api::V2::AuthenticatedApiBaseController

    def request_command
      render json: {
        "Dados" => {
          "IdComando" => 0,
          "Comando" => 0,
          "Lista" => nil
        },
        "Status" => {
          "Codigo" => 1,
          "Mensagem" => "OK"
        }
      }
    end
  end
end
