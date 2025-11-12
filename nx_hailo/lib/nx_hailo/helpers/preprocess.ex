defmodule NxHailo.Helpers.Preprocess do
  def evision_resize_and_pad(image, {target_h, target_h} = target_shape) do
    {h, w, _} = image.shape

    # target_h and target_w should be the same for yolov8
   size = max(h, w)
   pad_h = div(size - h, 2)
   pad_w = div(size - w, 2)

   pad_h_extra = rem(size - h, 2)
   pad_w_extra = rem(size - w, 2)

   # pad to a square
   padded = Evision.copyMakeBorder(
     image,
     pad_h,
     pad_h + pad_h_extra,
     pad_w,
     pad_w + pad_w_extra,
     Evision.Constant.cv_BORDER_CONSTANT(),
     value: {114, 114, 114}
   )

    Evision.resize(padded, target_shape)
 end

 def yolo_preprocess(mat, target_shape) do
  %{type: {:u, 8}} =
    input_tensor =
      mat
      |> evision_resize_and_pad(target_shape)
      |> Evision.Mat.to_nx()
      |> Nx.backend_transfer()

  input_tensor
 end

end
