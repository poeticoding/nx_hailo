defmodule NxHailo do
  @moduledoc """
  Top-level API for Hailo integration with Nx.
  Provides simple functions to load models and run inference.
  """

  @doc """
  Runs YOLO object detection on an input image using the provided Hailo model.

  ## Arguments
    - `hailo_model`: The loaded Hailo model struct (see `NxHailo.Hailo.load/1`).
    - `classes`: List of class names (strings or atoms) to use for detection/class mapping.
    - `mat`: The input image as an `Evision.Mat` struct.

  ## Returns
    - detected objects: list of `NxHailo.Parsers.YoloV8.DetectedObject`
  """
  def yolo_detect(hailo_model, classes, mat) do
    [%{name: name, shape: model_shape}] = hailo_model.pipeline.input_vstream_infos
    [%{name: output_key}] = hailo_model.pipeline.output_vstream_infos
    input_shape = {elem(mat.shape, 0), elem(mat.shape, 1)}
    target_shape = {model_shape.height, model_shape.width}
    input_tensor = NxHailo.Helpers.Preprocess.yolo_preprocess(mat, target_shape)

    {:ok, raw_detected_objects} =
      NxHailo.Hailo.infer(
        hailo_model,
        %{name => input_tensor},
        NxHailo.Parsers.YoloV8,
        classes: classes,
        key: output_key
      )
    raw_detected_objects
    |> Enum.reject(&(&1.score < 0.0))
    |> NxHailo.Parsers.YoloV8.postprocess(input_shape)
  end
end
