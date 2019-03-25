# Convert a 1-D timeseries into sliding window matrix for ML training
mutable struct Matrifier <: Transformer
  model
  args

  function Matrifier(args=Dict())
    default_args = Dict(
        :ahead => 1,
        :size => 7,
        :stride => 1,
    )
    new(nothing,mergedict(default_args,args))
  end
end

function fit!(mtr::Matrifier,xx::T,y::Vector=Vector()) where {T<:Union{Matrix,Vector}}
  mtr.model = mtr.args
end

function transform!(mtr::Matrifier,x::T) where {T<:Union{Matrix,Vector}}
  x isa Vector || error("data should be a vector")
  res=toMatrix(mtr,x)
  convert(Array{Float64},res)
end

function toMatrix(mtr::Transformer, x::Vector)
  stride=mtr.args[:stride];sz=mtr.args[:size];ahead=mtr.args[:ahead]
  xlength = length(x)
  xlength > sz || error("data too short for the given size of sliding window")
  ndx=collect(xlength:-1:1)
  mtuples = slidingwindow(i->(i-ahead),ndx,sz,stride)
  height=size(mtuples)[1]
  mmatrix = Array{Union{DateTime,<:Real},2}(zeros(height,sz+1))
  ctr=1
  gap = xlength - mtuples[1][2][1]
  for (s,k) in mtuples
    v = [reverse(s);k] .+ gap
    mmatrix[ctr,:].=x[v]
    ctr+=1
  end
  return mmatrix
end

function matrifyrun()
  mtr = Matrifier(Dict(:ahead=>24,:size=>24,:stride=>1))
  sz = mtr.args[:size]
  x=collect(1:100)
  y=collect(1:100)
  println(fit!(mtr,x,y))
  transform!(mtr,x)
end

# Convert a 1-D date series into sliding window matrix for ML training
mutable struct Dateifier <: Transformer
  model
  args

  function Dateifier(args=Dict())
    default_args = Dict(
        :ahead => 1,
        :size => 7,
        :stride => 1,
        :dateinterval => Dates.Hour(1)
    )
    new(nothing,mergedict(default_args,args))
  end
end

function fit!(dtr::Dateifier,x::T,y::Vector=[]) where {T<:Union{Matrix,Vector}}
  (eltype(x) <: DateTime || eltype(x) <: Date) || error("array element types are not dates")
  dtr.args[:lower] = minimum(x)
  dtr.args[:upper] = maximum(x)
  dtr.model = dtr.args
end

# transform to day of the month, day of the week, etc
function transform!(dtr::Dateifier,x::T) where {T<:Union{Matrix,Vector}}
  x isa Vector || error("data should be a vector")
  @assert eltype(x) <: DateTime || eltype(x) <: Date
  res=toMatrix(dtr,x)
  endpoints = convert(Array{DateTime},res)[:,end-1]
  dt = DataFrame()
  dt[:year]=Dates.year.(endpoints)
  dt[:month]=Dates.month.(endpoints)
  dt[:day]=Dates.day.(endpoints)
  dt[:hour]=Dates.hour.(endpoints)
  dt[:week]=Dates.week.(endpoints)
  dt[:dow]=Dates.dayofweek.(endpoints)
  dt[:doq]=Dates.dayofquarter.(endpoints)
  dt[:qoy]=Dates.quarterofyear.(endpoints)
  dtr.args[:header] = names(dt)
  convert(Matrix{Int64},dt)
end

function dateifierrun()
  dtr = Dateifier(Dict(:stride=>5))
  lower = DateTime(2017,1,1)
  upper = DateTime(2019,1,1)
  x=lower:Dates.Hour(1):upper |> collect
  y=lower:Dates.Hour(1):upper |> collect
  fit!(dtr,x,y)
  transform!(dtr,x)
end


# Date,Val time series
mutable struct DateValgator <: Transformer
  model
  args

  function DateValgator(args=Dict())
    default_args = Dict(
        :ahead => 1,
        :size => 7,
        :stride => 1,
        :dateinterval => Dates.Hour(1)
    )
    new(nothing,mergedict(default_args,args))
  end
end

function validdateval!(x::T) where {T<:DataFrame}
  size(x)[2] == 2 || error("Date Val timeseries need two columns")
  (eltype(x[:,1]) <: DateTime || eltype(x[:,1]) <: Date) || error("array element types are not dates")
  eltype(x[:,2]) <: Union{Missing,Real} || error("array element types are not values")
  cnames = names(x)
  rename!(x,Dict(cnames[1]=>:Date,cnames[2]=>:Value))
end


function fit!(dvmr::DateValgator,xx::T,y::Vector=[]) where {T<:DataFrame}
  x = deepcopy(xx)
  validdateval!(x)
  dvmr.model=dvmr.args
end

function transform!(dvmr::DateValgator,xx::T) where {T<:DataFrame}
  x = deepcopy(xx)
  validdateval!(x)
  grpby = typeof(dvmr.args[:dateinterval])
  sym = Symbol(grpby)
  x[sym] = round.(x[:Date],grpby)
  res=by(x,sym,MeanValue = :Value=>skipmean)
  rename!(res,Dict(names(res)[1]=>:Date,names(res)[2]=>:Value))
  res
end

function datevalgatorrun()
  dtvl = DateValgator(Dict(:dateinterval=>Dates.Hour(1)))
  dte=DateTime(2014,1,1):Dates.Minute(1):DateTime(2016,1,1)
  val = rand(length(dte))
  fit!(dtvl,DataFrame(date=dte,values=val),[])
  transform!(dtvl,DataFrame(date=dte,values=val))
end


# Date,Val time series
# Normalize and clean date,val by replacing missings with medians
mutable struct DateValizer <: Transformer
  model
  args

  function DateValizer(args=Dict())
    default_args = Dict(
        :ahead => 1,
        :size => 7,
        :stride => 1,
        :dateinterval => Dates.Hour(1)
    )
    new(nothing,mergedict(default_args,args))
  end
end

function getMedian(t::Type{T},xx::DataFrame) where {T<:Union{TimePeriod,DatePeriod}}
  x = deepcopy(xx)
  sgp = Symbol(t)
  fn = Dict(Dates.Hour=>Dates.hour,
            Dates.Minute=>Dates.minute,
            Dates.Second=>Dates.second,
            Dates.Month=>Dates.month)
  try
    x[sgp]=fn[t].(x[:Date])
  catch
    error("unknown dateinterval")
  end
  gpmeans = by(x,sgp,Value = :Value => skipmedian)
end

function fullaggregate!(dvzr::DateValizer,xx::T) where {T<:DataFrame}
  x = deepcopy(xx)
  grpby = typeof(dvzr.args[:dateinterval])
  sym = Symbol(grpby)
  x[sym] = round.(x[:Date],grpby)
  aggr = by(x,sym,MeanValue = :Value=>skipmean)
  rename!(aggr,Dict(names(aggr)[1]=>:Date,names(aggr)[2]=>:Value))
  lower = minimum(x[:Date])
  upper = maximum(x[:Date])
  #create list of complete dates and join with aggregated data
  cdate = DataFrame(Date = collect(lower:dvzr.args[:dateinterval]:upper))
  joined = join(cdate,aggr,on=:Date,kind=:left)
  joined
end

function fit!(dvzr::DateValizer,xx::T,y::Vector=[]) where {T<:DataFrame}
  x = deepcopy(xx)
  validdateval!(x)
  # get complete dates and aggregate
  joined = fullaggregate!(dvzr,x)
  grpby = typeof(dvzr.args[:dateinterval])
  sym = Symbol(grpby)
  medians = getMedian(grpby,joined)
  dvzr.args[:medians] = medians
  dvzr.model=dvzr.args
end

function transform!(dvzr::DateValizer,xx::T) where {T<:DataFrame}
  x = deepcopy(xx)
  validdateval!(x)
  # get complete dates, aggregate, and get medians
  joined = fullaggregate!(dvzr,x)
  # copy medians
  medians = dvzr.args[:medians]
  grpby = typeof(dvzr.args[:dateinterval])
  sym = Symbol(grpby)
  fn = Dict(Dates.Hour=>Dates.hour,
            Dates.Minute=>Dates.minute,
            Dates.Second=>Dates.second,
            Dates.Month=>Dates.month)
  try
    joined[sym]=fn[grpby].(joined[:Date])
  catch
    error("unknown dateinterval")
  end
  # find indices of missing
  missingndx = findall(ismissing.(joined[:Value]))
  jmndx=joined[missingndx,sym] .+ 1 # get time period index of missing, convert 0 index time to 1 index
  missingvals::SubArray = @view joined[missingndx,:Value] 
  missingvals .= medians[jmndx,:Value] # replace missing with median value
  sum(ismissing.(joined[:,:Value])) == 0 || error("Aggregation by time period failed to replace missings")
  joined[:,[:Date,:Value]]
end

function datevalizerrun()
  # test passing args from one structure to another
  Random.seed!(123)
  dvzr1 = DateValizer(Dict(:dateinterval=>Dates.Hour(1)))
  dvzr2 = DateValizer(dvzr1.args)
  dte=DateTime(2014,1,1):Dates.Minute(15):DateTime(2016,1,1)
  val = Array{Union{Missing,Float64}}(rand(length(dte)))
  y = []
  x = DataFrame(MDate=dte,MValue=val)
  nmissing=50000
  ndxmissing=Random.shuffle(1:length(dte))[1:nmissing]
  x[:MValue][ndxmissing] .= missing
  fit!(dvzr2,x,y)
  transform!(dvzr2,x)
end


# fill-in missings with nearest-neighbors median
mutable struct DateValNNer <: Transformer
  model
  args

  function DateValNNer(args=Dict())
    default_args = Dict(
        :ahead => 1,
        :size => 7,
        :stride => 1,
        :dateinterval => Dates.Hour(1),
        :nnsize => 5 
    )
    new(nothing,mergedict(default_args,args))
  end
end

function fit!(dnnr::DateValNNer,xx::T,y::Vector=[]) where {T<:DataFrame}
  x = deepcopy(xx)
  validdateval!(x)
  dnnr.model=dnnr.args
end

function transform!(dnnr::DateValNNer,xx::T) where {T<:DataFrame}
  x = deepcopy(xx)
  validdateval!(x)
  grpby = typeof(dnnr.args[:dateinterval])
  sym = Symbol(grpby)
  # aggregate by time period
  x[sym] = round.(x[:Date],grpby)
  aggr = by(x,sym,MeanValue = :Value=>skipmean)
  rename!(aggr,Dict(names(aggr)[1]=>:Date,names(aggr)[2]=>:Value))
  lower = minimum(x[:Date])
  upper = maximum(x[:Date])
  #create list of complete dates and join with aggregated data
  cdate = DataFrame(Date = collect(lower:dnnr.args[:dateinterval]:upper))
  joined = join(cdate,aggr,on=:Date,kind=:left)

  # to fill-in with nearest neighbors
  nnsize::Int64 = dnnr.args[:nnsize]
  missingndx = DataFrame(missed = findall(ismissing.(joined[:Value])))
  missingndx[:neighbors] = (x->(x-nnsize):(x-1)).(missingndx[:missed]) # NN ranges
  #joined[missingndx[:missed],:Value] = (r -> skipmedian(joined[r,:Value])).(missingndx[:neighbors]) # iterate to each range
  missingvals::SubArray = @view joined[missingndx[:missed],:Value] # get view of only missings
  missingvals .=  (r -> skipmedian(joined[r,:Value])).(missingndx[:neighbors]) # replace with nn medians
  sum(ismissing.(joined[:,:Value])) == 0 || error("Nearest Neigbour algo failed to replace missings")
  joined
end

function datevalnnerrun()
  # test passing args from one structure to another
  Random.seed!(123)
  dnnr = DateValNNer(Dict(:dateinterval=>Dates.Hour(1),:nnsize=>3))
  dte=DateTime(2014,1,1):Dates.Hour(1):DateTime(2016,1,1)
  val = Array{Union{Missing,Float64}}(rand(length(dte)))
  y = []
  x = DataFrame(MDate=dte,MValue=val)
  nmissing=10
  ndxmissing=Random.shuffle(1:length(dte))[1:nmissing]
  x[:MValue][ndxmissing] .= missing
  fit!(dnnr,x,y)
  transform!(dnnr,x)
end
