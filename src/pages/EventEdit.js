import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import {
  Calendar,
  MapPin,
  Clock,
  Users,
  Tag,
  Image as ImageIcon,
  Upload,
  Sparkles,
  Save,
  Eye,
  X,
  Loader2,
  CheckCircle,
  ArrowLeft
} from 'lucide-react';
import { auth } from '../lib/supabase';
import { eventsService } from '../services/eventsService';
import { storageService } from '../services/storageService';
import { statusService } from '../services/statusService';
import LocationSearch from '../components/LocationSearch';
import { useToast } from '../contexts/ToastContext';
import { DEPARTMENTS } from '../config/departments';

const EventEdit = () => {
  const navigate = useNavigate();
  const { id } = useParams();
  const { error: showError, success: showSuccess } = useToast();
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    date: '',
    timeHour: '09',
    timeMinute: '00',
    timePeriod: 'AM',
    endTimeHour: '11',
    endTimeMinute: '00',
    endTimePeriod: 'AM',
    location: '',
    maxParticipants: '',
    category: '',
    tags: [],
    image: null,
    image_url: null,
    isVirtual: false,
    virtualLink: '',
    requirements: '',
    contactEmail: '',
    contactPhone: ''
  });

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const [user, setUser] = useState(null);
  const [imagePreview, setImagePreview] = useState(null);
  const [imageUploading, setImageUploading] = useState(false);
  const [originalEventDate, setOriginalEventDate] = useState(null);

  // Get tomorrow's date in YYYY-MM-DD format for minimum date
  const getTomorrowDate = () => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    return tomorrow.toISOString().split('T')[0];
  };

  const [aiSuggestions, setAiSuggestions] = useState([
    'Update your description to highlight new speakers',
    'Adding a new image can boost re-engagement',
    'Check if the location details need refinement',
  ]);

  useEffect(() => {
    const fetchEvent = async () => {
      try {
        const { user } = await auth.getCurrentUser();
        if (!user) {
          navigate('/login');
          return;
        }
        setUser(user);

        const { data: event, error } = await eventsService.getEventById(id);
        if (error) throw error;

        if (event.user_id !== user.id) {
          // Check if admin... for now assume strict owner check unless role check added
          // But allow view for now, save will fail if RLS
        }

        // Parse time (HH:mm:ss) to UI format
        const parseTime = (timeStr) => {
          if (!timeStr) return { h: '09', m: '00', p: 'AM' };
          const [h, m] = timeStr.split(':');
          let hour = parseInt(h);
          let period = 'AM';
          if (hour >= 12) {
            period = 'PM';
            if (hour > 12) hour -= 12;
          }
          if (hour === 0) hour = 12;
          return {
            h: hour.toString().padStart(2, '0'),
            m: m,
            p: period
          };
        };

        const startTime = parseTime(event.time);
        const endTime = parseTime(event.end_time);

        setOriginalEventDate(event.date);
        setFormData({
          title: event.title,
          description: event.description || '',
          date: event.date,
          timeHour: startTime.h,
          timeMinute: startTime.m,
          timePeriod: startTime.p,
          endTimeHour: endTime.h,
          endTimeMinute: endTime.m,
          endTimePeriod: endTime.p,
          location: event.location,
          maxParticipants: event.max_participants || '',
          category: event.category || '',
          tags: event.tags || [],
          image: null, // Don't need internal path unless updating
          image_url: event.image_url,
          isVirtual: event.is_virtual,
          virtualLink: event.virtual_link || '',
          requirements: event.requirements || '',
          contactEmail: event.contact_email || '',
          contactPhone: event.contact_phone || ''
        });

        if (event.image_url) {
          setImagePreview(event.image_url);
        }

      } catch (err) {
        console.error('Error fetching event:', err);
        setError('Failed to load event details');
      } finally {
        setLoading(false);
      }
    };
    fetchEvent();
  }, [id, navigate]);

  const handleInputChange = (e) => {
    const { name, value, type, checked } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: type === 'checkbox' ? checked : value
    }));
  };

  const handleTagAdd = (tag) => {
    if (tag && !formData.tags.includes(tag)) {
      setFormData(prev => ({ ...prev, tags: [...prev.tags, tag] }));
    }
  };

  const handleTagRemove = (tag) => {
    setFormData(prev => ({ ...prev, tags: prev.tags.filter(t => t !== tag) }));
  };

  const handleImageUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    if (file.size > 5 * 1024 * 1024) {
      showError('Image size should be less than 5MB');
      return;
    }

    try {
      setImageUploading(true);
      const { data, error } = await storageService.uploadEventImage(file, user.id, id);
      if (error) throw error;

      setImagePreview(data.publicUrl);
      setFormData(prev => ({ ...prev, image_url: data.publicUrl }));
    } catch (err) {
      console.error('Error uploading image:', err);
      showError('Failed to upload image');
    } finally {
      setImageUploading(false);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setSaving(true);

    try {
      const formatTime24 = (hour, minute, period) => {
        let h = parseInt(hour);
        if (period === 'PM' && h < 12) h += 12;
        if (period === 'AM' && h === 12) h = 0;
        return `${h.toString().padStart(2, '0')}:${minute}`;
      };

      const eventData = {
        title: formData.title,
        description: formData.description,
        date: formData.date,
        time: formatTime24(formData.timeHour, formData.timeMinute, formData.timePeriod),
        end_time: formatTime24(formData.endTimeHour, formData.endTimeMinute, formData.endTimePeriod),
        location: formData.location,
        max_participants: formData.maxParticipants ? parseInt(formData.maxParticipants) : null,
        category: formData.category,
        tags: formData.tags,
        image_url: formData.image_url,
        is_virtual: formData.isVirtual,
        virtual_link: formData.isVirtual ? formData.virtualLink : null,
        requirements: formData.requirements,
        contact_email: formData.contactEmail,
        contact_phone: formData.contactPhone
      };

      const { error } = await eventsService.updateEvent(id, eventData);
      if (error) throw error;

      showSuccess('Event updated successfully');
      navigate(`/events/${id}`);
    } catch (err) {
      console.error('Error updating event:', err);
      showError('Failed to update event');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <Loader2 className="h-8 w-8 animate-spin text-primary-600" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="max-w-7xl mx-auto px-4 py-8">
        <div className="bg-red-50 text-red-800 p-4 rounded-lg">
          <p>{error}</p>
          <button onClick={() => navigate('/events')} className="mt-2 text-sm underline">Back to Events</button>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto space-y-6 px-4 sm:px-6 lg:px-8 py-8">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900">Edit Event</h1>
        <button
          onClick={() => navigate(`/events/${id}`)}
          className="flex items-center text-gray-600 hover:text-gray-900"
        >
          <ArrowLeft className="h-5 w-5 mr-1" />
          Back to Event
        </button>
      </div>

      <form onSubmit={handleSubmit} className="bg-white shadow rounded-lg p-6 space-y-6">
        {/* Basic Info */}
        <div className="space-y-4">
          <h2 className="text-lg font-medium text-gray-900 border-b pb-2">Basic Information</h2>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Title</label>
            <input
              type="text"
              name="title"
              value={formData.title}
              onChange={handleInputChange}
              className="input-field w-full"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
            <textarea
              name="description"
              value={formData.description}
              onChange={handleInputChange}
              rows={4}
              className="input-field w-full"
              required
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Date</label>
              <input
                type="date"
                name="date"
                value={formData.date}
                onChange={handleInputChange}
                // Allow past dates if it was already past (handled by validation if needed, but for edit maybe allow logic)
                className="input-field w-full"
                required
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Department</label>
              <select
                name="category"
                value={formData.category}
                onChange={handleInputChange}
                className="input-field w-full"
                required
              >
                <option value="">Select Department</option>
                {DEPARTMENTS.map(dept => (
                  <option key={dept.id} value={dept.id}>{dept.name}</option>
                ))}
              </select>
            </div>
          </div>
        </div>

        {/* Location & Time */}
        <div className="space-y-4">
          <h2 className="text-lg font-medium text-gray-900 border-b pb-2">Location & Time</h2>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Location
            </label>
            <LocationSearch
              value={formData.location}
              onChange={(loc) => setFormData(prev => ({ ...prev, location: loc }))}
              placeholder="Search location..."
              required
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="flex gap-2">
              <div className="flex-1">
                <label className="block text-sm font-medium text-gray-700 mb-1">Start Time</label>
                <div className="flex gap-1">
                  <select name="timeHour" value={formData.timeHour} onChange={handleInputChange} className="input-field p-1">
                    {Array.from({ length: 12 }, (_, i) => i + 1).map(h => <option key={h} value={h.toString().padStart(2, '0')}>{h}</option>)}
                  </select>
                  <select name="timeMinute" value={formData.timeMinute} onChange={handleInputChange} className="input-field p-1">
                    {['00', '15', '30', '45'].map(m => <option key={m} value={m}>{m}</option>)}
                  </select>
                  <select name="timePeriod" value={formData.timePeriod} onChange={handleInputChange} className="input-field p-1">
                    <option value="AM">AM</option>
                    <option value="PM">PM</option>
                  </select>
                </div>
              </div>
            </div>
            <div className="flex gap-2">
              <div className="flex-1">
                <label className="block text-sm font-medium text-gray-700 mb-1">End Time</label>
                <div className="flex gap-1">
                  <select name="endTimeHour" value={formData.endTimeHour} onChange={handleInputChange} className="input-field p-1">
                    {Array.from({ length: 12 }, (_, i) => i + 1).map(h => <option key={h} value={h.toString().padStart(2, '0')}>{h}</option>)}
                  </select>
                  <select name="endTimeMinute" value={formData.endTimeMinute} onChange={handleInputChange} className="input-field p-1">
                    {['00', '15', '30', '45'].map(m => <option key={m} value={m}>{m}</option>)}
                  </select>
                  <select name="endTimePeriod" value={formData.endTimePeriod} onChange={handleInputChange} className="input-field p-1">
                    <option value="AM">AM</option>
                    <option value="PM">PM</option>
                  </select>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Media */}
        <div className="space-y-4">
          <h2 className="text-lg font-medium text-gray-900 border-b pb-2">Media</h2>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Event Image</label>
            <div className="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center">
              {imagePreview ? (
                <div className="space-y-4">
                  <img src={imagePreview} alt="Event preview" className="mx-auto h-32 w-auto object-cover rounded-lg" />
                  <button type="button" onClick={() => { setImagePreview(null); setFormData(prev => ({ ...prev, image_url: null })); }} className="text-red-600 hover:text-red-800 text-sm">Remove Image</button>
                </div>
              ) : (
                <div>
                  <Upload className="mx-auto h-12 w-12 text-gray-400" />
                  <div className="mt-4">
                    <label htmlFor="file-upload" className="cursor-pointer bg-primary-600 text-white px-4 py-2 rounded-md hover:bg-primary-700">
                      {imageUploading ? 'Uploading...' : 'Upload Image'}
                    </label>
                    <input id="file-upload" type="file" className="hidden" accept="image/*" onChange={handleImageUpload} disabled={imageUploading} />
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Additional Info */}
        <div className="space-y-4">
          <h2 className="text-lg font-medium text-gray-900 border-b pb-2">Additional Information</h2>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Max Participants</label>
              <input type="number" name="maxParticipants" value={formData.maxParticipants} onChange={handleInputChange} className="input-field w-full" />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Tags</label>
              <input
                type="text"
                onKeyPress={(e) => { if (e.key === 'Enter') { e.preventDefault(); handleTagAdd(e.target.value); e.target.value = ''; } }}
                className="input-field w-full"
                placeholder="Press Enter to add"
              />
              <div className="flex flex-wrap gap-2 mt-2">
                {formData.tags.map(tag => (
                  <span key={tag} className="bg-gray-100 rounded-full px-3 py-1 text-sm flex items-center">
                    {tag} <X size={14} className="ml-1 cursor-pointer" onClick={() => handleTagRemove(tag)} />
                  </span>
                ))}
              </div>
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Requirements</label>
            <textarea name="requirements" value={formData.requirements} onChange={handleInputChange} rows={3} className="input-field w-full" />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Contact Email</label>
              <input type="email" name="contactEmail" value={formData.contactEmail} onChange={handleInputChange} className="input-field w-full" />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Contact Phone</label>
              <input type="tel" name="contactPhone" value={formData.contactPhone} onChange={handleInputChange} className="input-field w-full" />
            </div>
          </div>
        </div>

        <div className="flex justify-end gap-3 pt-6 border-t">
          <button
            type="button"
            onClick={() => navigate(`/events/${id}`)}
            className="px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saving}
            className="px-4 py-2 bg-primary-600 text-white rounded-md hover:bg-primary-700 disabled:opacity-50 flex items-center"
          >
            {saving ? (
              <>
                <Loader2 className="animate-spin h-4 w-4 mr-2" />
                Saving...
              </>
            ) : 'Save Changes'}
          </button>
        </div>

      </form>
    </div>
  );
};

export default EventEdit;
